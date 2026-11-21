package com.announcementzone.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private class SupabaseHttpException(val statusCode: Int, message: String) : IllegalStateException(message)

data class Announcement(
    val id: String,
    val title: String,
    val content: String,
    val date: String,
    val category: String,
    val linkUrl: String?,
    val linkLabel: String?,
    val pinned: Boolean
)

data class MemberSession(
    val userId: String,
    val email: String,
    val nickname: String?,
    val memberNumber: String?,
    val role: String?,
    val createdAt: String?
)

class SupabaseAuthRepository(context: Context) {
    private val appContext = context.applicationContext
    private val sessionStore = SecureSessionStore(appContext)
    private val baseUrl = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val anonKey = BuildConfig.SUPABASE_ANON_KEY

    suspend fun loadAnnouncements(): List<Announcement> = withContext(Dispatchers.IO) {
        val now = URLEncoder.encode(java.time.Instant.now().toString(), "UTF-8")
        val path = "/rest/v1/announcements?select=id,title,content,date,category,link_url,link_label,pinned,published_at&published=eq.true&published_at=lte.$now&order=pinned.desc,published_at.desc,created_at.desc&limit=100"
        val accessToken = sessionStore.read()?.first
        val rows = requestArray(path, accessToken)
        buildList {
            for (index in 0 until rows.length()) {
                val row = rows.optJSONObject(index) ?: continue
                val publishedAt = row.optString("published_at")
                add(
                    Announcement(
                        id = row.opt("id")?.toString().orEmpty(),
                        title = row.optString("title", "未命名公告"),
                        content = row.optString("content"),
                        date = row.optString("date").ifBlank { publishedAt.take(10) },
                        category = row.optString("category").ifBlank { "最新消息" },
                        linkUrl = row.optString("link_url").takeIf { it.isNotBlank() && it != "null" },
                        linkLabel = row.optString("link_label").takeIf { it.isNotBlank() && it != "null" },
                        pinned = row.optBoolean("pinned", false)
                    )
                )
            }
        }
    }

    suspend fun signIn(email: String, password: String): MemberSession =
        withContext(Dispatchers.IO) {
            require(email.isNotBlank()) { "請輸入 Email。" }
            require(password.isNotEmpty()) { "請輸入密碼。" }

            val tokenJson = request(
                path = "/auth/v1/token?grant_type=password",
                method = "POST",
                body = JSONObject().put("email", email.trim()).put("password", password)
            )
            val accessToken = tokenJson.optString("access_token")
            val refreshToken = tokenJson.optString("refresh_token")
            if (accessToken.isBlank() || refreshToken.isBlank()) {
                throw IllegalStateException("登入未成功，請確認帳號密碼。")
            }

            sessionStore.save(accessToken, refreshToken)
            try {
                loadMember(accessToken)
            } catch (error: Exception) {
                sessionStore.clear()
                throw error
            }
        }

    suspend fun restoreSession(): MemberSession? = withContext(Dispatchers.IO) {
        val saved = sessionStore.read() ?: return@withContext null
        try {
            loadMember(saved.first)
        } catch (error: SupabaseHttpException) {
            // Only refresh an expired/invalid access token. Do not erase a valid
            // saved session because of temporary network or profile-query errors.
            if (error.statusCode != 401) throw error

            val refreshed = try {
                request(
                    path = "/auth/v1/token?grant_type=refresh_token",
                    method = "POST",
                    body = JSONObject().put("refresh_token", saved.second)
                )
            } catch (refreshError: SupabaseHttpException) {
                if (refreshError.statusCode in 400..401) {
                    sessionStore.clear()
                    return@withContext null
                }
                throw refreshError
            }
            val access = refreshed.optString("access_token")
            val refresh = refreshed.optString("refresh_token")
            if (access.isBlank() || refresh.isBlank()) {
                sessionStore.clear()
                return@withContext null
            }
            // Persist the rotated refresh token before making profile requests.
            sessionStore.save(access, refresh)
            loadMember(access)
        }
    }

    suspend fun signOut() = withContext(Dispatchers.IO) {
        val saved = sessionStore.read()
        if (saved != null) {
            runCatching {
                request(
                    path = "/auth/v1/logout?scope=local",
                    method = "POST",
                    accessToken = saved.first
                )
            }
        }
        sessionStore.clear()
    }

    private fun loadMember(accessToken: String): MemberSession {
        val user = request("/auth/v1/user", "GET", accessToken = accessToken)
        val userId = user.optString("id")
        if (userId.isBlank()) throw IllegalStateException("無法取得會員資料，請重新登入。")

        val encodedId = URLEncoder.encode(userId, "UTF-8")
        val profileRows = requestArray(
            "/rest/v1/profiles?id=eq.$encodedId&select=id,nickname,member_no,role,created_at",
            accessToken
        )
        val profile = profileRows.optJSONObject(0)

        // The website treats a missing/unreadable visitor-account row as unspecified.
        // If a row is returned, however, an explicit inactive state must block access.
        val visitorRows = runCatching {
            requestArray(
                "/rest/v1/visitor_accounts?id=eq.$encodedId&select=active",
                accessToken
            )
        }.getOrNull()
        val activeValue = visitorRows?.optJSONObject(0)?.opt("active")
        if (activeValue == false) {
            throw IllegalStateException("此帳號目前已停用，請聯絡管理員。")
        }

        val memberNo = profile?.opt("member_no")?.toString()?.takeIf { it != "null" }
        return MemberSession(
            userId = userId,
            email = user.optString("email"),
            nickname = profile?.optString("nickname")?.takeIf { it.isNotBlank() },
            memberNumber = memberNo?.padStart(3, '0'),
            role = profile?.optString("role")?.takeIf { it.isNotBlank() },
            createdAt = profile?.optString("created_at")?.takeIf { it.isNotBlank() }
        )
    }

    private fun request(
        path: String,
        method: String,
        body: JSONObject? = null,
        accessToken: String? = null
    ): JSONObject {
        val connection = URL(baseUrl + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.setRequestProperty("apikey", anonKey)
            connection.setRequestProperty("Accept", "application/json")
            if (accessToken != null) {
                connection.setRequestProperty("Authorization", "Bearer $accessToken")
            }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val detail = runCatching {
                    val json = JSONObject(response)
                    json.optString("msg").ifBlank {
                        json.optString("message").ifBlank {
                            json.optString("error_description").ifBlank { json.optString("error") }
                        }
                    }
                }.getOrDefault("")
                throw SupabaseHttpException(status, detail.ifBlank { "連線失敗（HTTP $status），請稍後再試。" })
            }
            return if (response.isBlank()) JSONObject() else JSONObject(response)
        } finally {
            connection.disconnect()
        }
    }

    private fun requestArray(path: String, accessToken: String?): JSONArray {
        val connection = URL(baseUrl + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.setRequestProperty("apikey", anonKey)
            if (!accessToken.isNullOrBlank()) {
                connection.setRequestProperty("Authorization", "Bearer $accessToken")
            }
            connection.setRequestProperty("Accept", "application/json")
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw SupabaseHttpException(status, "讀取會員資料失敗（HTTP $status）。")
            }
            return JSONArray(response)
        } finally {
            connection.disconnect()
        }
    }
}

private class SecureSessionStore(context: Context) {
    private val preferences = context.getSharedPreferences("smart_class_secure_session", Context.MODE_PRIVATE)
    private val alias = "smart_class_session_aes_key"

    fun save(accessToken: String, refreshToken: String) {
        val payload = JSONObject()
            .put("access", accessToken)
            .put("refresh", refreshToken)
            .toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
        preferences.edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("data", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .apply()
    }

    fun read(): Pair<String, String>? {
        val ivText = preferences.getString("iv", null) ?: return null
        val dataText = preferences.getString("data", null) ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(ivText, Base64.NO_WRAP)
            val encrypted = Base64.decode(dataText, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            val json = JSONObject(String(cipher.doFinal(encrypted), Charsets.UTF_8))
            val access = json.optString("access")
            val refresh = json.optString("refresh")
            if (access.isBlank() || refresh.isBlank()) null else access to refresh
        } catch (_: Exception) {
            clear()
            null
        }
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(alias, null) as? SecretKey
        if (existing != null) return existing

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }
}
