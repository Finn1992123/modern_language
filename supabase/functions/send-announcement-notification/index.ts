import { createClient } from "npm:@supabase/supabase-js@2";

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  try {
    const supabaseUrl = requireEnv("SUPABASE_URL");
    const anonKey = requireEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = request.headers.get("Authorization") ?? "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json();
    const notificationId = String(body.notification_id ?? "").trim();
    if (!notificationId) {
      return Response.json(
        { error: "notification_id is required" },
        { status: 400 },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { data: announcement, error: announcementError } = await admin
      .from("announcements")
      .select(
        "notification_id, created_by_auth_user_id, push_sent_at",
      )
      .eq("notification_id", notificationId)
      .single();

    if (announcementError || !announcement) {
      return Response.json({ error: "Announcement not found" }, {
        status: 404,
      });
    }
    if (announcement.created_by_auth_user_id !== userData.user.id) {
      return Response.json({ error: "Forbidden" }, { status: 403 });
    }
    if (announcement.push_sent_at) {
      return Response.json({ sent: 0, already_sent: true });
    }

    const { data: tokenRows, error: tokenError } = await admin.rpc(
      "get_announcement_recipient_tokens",
      { input_notification_id: notificationId },
    );
    if (tokenError) throw tokenError;

    const tokenSet = new Set<string>();
    for (const row of tokenRows ?? []) {
      const token = (row as { token?: unknown }).token;
      if (typeof token === "string" && token.length > 0) {
        tokenSet.add(token);
      }
    }
    const tokens = Array.from(tokenSet);

    const serviceAccount = JSON.parse(
      requireEnv("FIREBASE_SERVICE_ACCOUNT_JSON"),
    ) as ServiceAccount;
    const accessToken = await createGoogleAccessToken(serviceAccount);
    const invalidTokens: string[] = [];
    let sent = 0;

    for (let start = 0; start < tokens.length; start += 50) {
      const batch = tokens.slice(start, start + 50);
      const results = await Promise.all(
        batch.map((token) =>
          sendFcmMessage({
            accessToken,
            serviceAccount,
            token,
            notificationId,
            title: "Νέα ανακοίνωση",
            body: "Υπάρχει μια νέα ανακοίνωση που πρέπει να δείτε.",
          })
        ),
      );

      results.forEach((result, index) => {
        if (result.sent) sent += 1;
        if (result.invalidToken) invalidTokens.push(batch[index]);
      });
    }

    if (invalidTokens.length > 0) {
      await admin
        .from("push_notification_devices")
        .delete()
        .in("token", invalidTokens);
    }

    const { error: updateError } = await admin
      .from("announcements")
      .update({ push_sent_at: new Date().toISOString() })
      .eq("notification_id", notificationId);
    if (updateError) throw updateError;

    return new Response(
      JSON.stringify({ sent, recipients: tokens.length }),
      { headers: jsonHeaders },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500 },
    );
  }
});

async function sendFcmMessage(input: {
  accessToken: string;
  serviceAccount: ServiceAccount;
  token: string;
  notificationId: string;
  title: string;
  body: string;
}): Promise<{ sent: boolean; invalidToken: boolean }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${input.serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: input.token,
          notification: { title: input.title, body: input.body },
          data: {
            type: "announcement",
            notification_id: input.notificationId,
          },
          android: {
            priority: "high",
            notification: { channel_id: "announcements" },
          },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );

  if (response.ok) return { sent: true, invalidToken: false };

  const responseText = await response.text();
  const invalidToken = response.status === 404 ||
    responseText.includes("UNREGISTERED") ||
    responseText.includes("INVALID_ARGUMENT");
  if (!invalidToken) {
    throw new Error(`FCM request failed (${response.status}): ${responseText}`);
  }
  return { sent: false, invalidToken: true };
}

async function createGoogleAccessToken(
  serviceAccount: ServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encodedHeader = base64Url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const encodedPayload = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );
  const assertion = `${unsignedToken}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google OAuth failed (${response.status})`);
  }
  const data = await response.json();
  if (typeof data.access_token !== "string") {
    throw new Error("Google OAuth returned no access token");
  }
  return data.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const bytes = Uint8Array.from(
    atob(base64),
    (character) => character.charCodeAt(0),
  );
  return bytes.buffer as ArrayBuffer;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  bytes.forEach((byte) => (binary += String.fromCharCode(byte)));
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}
