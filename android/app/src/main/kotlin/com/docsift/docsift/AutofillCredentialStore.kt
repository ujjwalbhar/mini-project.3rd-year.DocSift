package com.docsift.docsift

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class AutofillEntry(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val domains: List<String>,
    val packages: List<String>,
    val updatedAt: Long,
)

data class PendingSaveEntry(
    val title: String,
    val username: String,
    val password: String,
    val domain: String,
    val packageName: String,
    val capturedAt: Long,
)

/**
 * Hardware-backed (`AndroidKeyStore` AES-256-GCM) credential index for
 * [DocSiftAutofillService]. Keeps zero plaintext on disk and avoids loading
 * Flutter or ONNX inside transient OS autofill callbacks.
 */
object AutofillCredentialStore {
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "docsift_autofill_aes256_master"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_SIZE = 12
    private const val TAG_BITS = 128

    private const val VAULT_FILE = "autofill_vault.enc"
    private const val PENDING_SAVES_FILE = "autofill_pending_saves.enc"

    private val KNOWN_BROWSERS = setOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "org.mozilla.firefox",
        "org.mozilla.fenix",
        "com.brave.browser",
        "com.microsoft.emmx",
        "com.sec.android.app.sbrowser",
        "com.opera.browser",
        "com.duckduckgo.mobile.android",
        "com.vivaldi.browser",
    )

    fun isBrowserPackage(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return KNOWN_BROWSERS.contains(packageName)
    }

    @Synchronized
    fun saveAllCredentials(context: Context, entries: List<AutofillEntry>) {
        val array = JSONArray()
        for (entry in entries) {
            val obj = JSONObject().apply {
                put("id", entry.id)
                put("title", entry.title)
                put("username", entry.username)
                put("password", entry.password)
                put("domains", JSONArray(entry.domains))
                put("packages", JSONArray(entry.packages))
                put("updatedAt", entry.updatedAt)
            }
            array.put(obj)
        }
        writeEncryptedFile(File(context.filesDir, VAULT_FILE), array.toString())
    }

    @Synchronized
    fun loadAllCredentials(context: Context): List<AutofillEntry> {
        val json = readEncryptedFile(File(context.filesDir, VAULT_FILE)) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            val result = ArrayList<AutofillEntry>(array.length())
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val domainsArr = obj.optJSONArray("domains") ?: JSONArray()
                val domains = ArrayList<String>(domainsArr.length())
                for (j in 0 until domainsArr.length()) {
                    val d = normalizeDomain(domainsArr.optString(j))
                    if (d.isNotEmpty()) domains.add(d)
                }
                val pkgArr = obj.optJSONArray("packages") ?: JSONArray()
                val pkgs = ArrayList<String>(pkgArr.length())
                for (j in 0 until pkgArr.length()) {
                    val p = pkgArr.optString(j).trim()
                    if (p.isNotEmpty()) pkgs.add(p)
                }
                val pw = obj.optString("password", "")
                if (pw.isEmpty()) continue
                result.add(
                    AutofillEntry(
                        id = obj.optString("id", UUID.randomUUID().toString()),
                        title = obj.optString("title", "Saved Login"),
                        username = obj.optString("username", ""),
                        password = pw,
                        domains = domains,
                        packages = pkgs,
                        updatedAt = obj.optLong("updatedAt", 0L),
                    )
                )
            }
            result
        } catch (_: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun getCredentialById(context: Context, id: String): AutofillEntry? {
        return loadAllCredentials(context).firstOrNull { it.id == id }
    }

    /**
     * Finds all saved accounts matching either the verified [webDomain] (when
     * inside a browser/WebView) or the verified Android [packageName].
     * Returns all matching accounts so the user can freely select which account
     * to log in with when multiple accounts exist for the same app/site.
     */
    @Synchronized
    fun findMatchingCredentials(
        context: Context,
        packageName: String?,
        webDomain: String?,
    ): List<AutofillEntry> {
        val all = loadAllCredentials(context)
        if (all.isEmpty()) return emptyList()

        val normWeb = normalizeDomain(webDomain)
        val cleanPkg = packageName?.trim().orEmpty()

        return all.filter { entry ->
            if (normWeb.isNotEmpty()) {
                entry.domains.any { savedDomain -> domainsMatch(savedDomain, normWeb) }
            } else if (cleanPkg.isNotEmpty() && !isBrowserPackage(cleanPkg)) {
                if (entry.packages.any { it.equals(cleanPkg, ignoreCase = true) }) {
                    true
                } else {
                    // Fallback domain-token check against verified reverse-DNS package segments
                    // (e.g. com.netflix.mediaclient -> netflix.com)
                    val pkgTokens = cleanPkg.lowercase().split('.')
                    entry.domains.any { d ->
                        val brand = d.substringBefore('.')
                        brand.length >= 4 && pkgTokens.contains(brand)
                    }
                }
            } else {
                false
            }
        }.sortedByDescending { it.updatedAt }
    }

    /**
     * Links [packageName] to an existing [credentialId] after the user manually
     * picks it from the vault picker, so future logins auto-match immediately.
     */
    @Synchronized
    fun bindPackageToCredential(
        context: Context,
        credentialId: String,
        packageName: String?,
        webDomain: String?,
    ) {
        val all = loadAllCredentials(context).toMutableList()
        val idx = all.indexOfFirst { it.id == credentialId }
        if (idx < 0) return

        val current = all[idx]
        val nextDomains = current.domains.toMutableSet()
        val nextPackages = current.packages.toMutableSet()

        val normDomain = normalizeDomain(webDomain)
        if (normDomain.isNotEmpty()) {
            nextDomains.add(normDomain)
        } else if (!packageName.isNullOrBlank() && !isBrowserPackage(packageName)) {
            nextPackages.add(packageName.trim())
        }

        all[idx] = current.copy(
            domains = nextDomains.toList(),
            packages = nextPackages.toList(),
            updatedAt = System.currentTimeMillis(),
        )
        saveAllCredentials(context, all)
    }

    /**
     * Persists a newly registered or updated login captured by `onSaveRequest`
     * into both the active autofill store and the pending Flutter import queue.
     */
    @Synchronized
    fun recordCapturedLogin(
        context: Context,
        title: String,
        username: String,
        password: String,
        webDomain: String?,
        packageName: String?,
    ) {
        if (password.isBlank()) return
        val normDomain = normalizeDomain(webDomain)
        val cleanPkg = if (normDomain.isEmpty() && !isBrowserPackage(packageName)) {
            packageName?.trim().orEmpty()
        } else {
            ""
        }

        val currentAll = loadAllCredentials(context).toMutableList()
        val existingExact = currentAll.any { entry ->
            entry.username.equals(username.trim(), ignoreCase = true) &&
                entry.password == password &&
                (
                    (normDomain.isNotEmpty() && entry.domains.any { domainsMatch(it, normDomain) }) ||
                        (cleanPkg.isNotEmpty() && entry.packages.any { it.equals(cleanPkg, ignoreCase = true) })
                    )
        }
        if (existingExact) {
            return
        }

        val now = System.currentTimeMillis()
        currentAll.add(
            0,
            AutofillEntry(
                id = "captured_${UUID.randomUUID()}",
                title = title.ifBlank { normDomain.ifBlank { cleanPkg.ifBlank { "Saved Login" } } },
                username = username.trim(),
                password = password,
                domains = if (normDomain.isNotEmpty()) listOf(normDomain) else emptyList(),
                packages = if (cleanPkg.isNotEmpty()) listOf(cleanPkg) else emptyList(),
                updatedAt = now,
            )
        )
        saveAllCredentials(context, currentAll)

        // Append to pending saves queue so DocSift imports into SQLCipher + .enc on next unlock
        val pendingFile = File(context.filesDir, PENDING_SAVES_FILE)
        val pendingArr = try {
            val raw = readEncryptedFile(pendingFile)
            if (raw != null) JSONArray(raw) else JSONArray()
        } catch (_: Exception) {
            JSONArray()
        }

        pendingArr.put(
            JSONObject().apply {
                put("title", title)
                put("username", username.trim())
                put("password", password)
                put("domain", normDomain)
                put("packageName", cleanPkg)
                put("capturedAt", now)
            }
        )
        writeEncryptedFile(pendingFile, pendingArr.toString())
    }

    @Synchronized
    fun consumePendingSaves(context: Context): List<PendingSaveEntry> {
        val file = File(context.filesDir, PENDING_SAVES_FILE)
        val raw = readEncryptedFile(file)
        if (file.exists()) {
            file.delete()
        }
        if (raw.isNullOrBlank()) return emptyList()

        return try {
            val arr = JSONArray(raw)
            val list = ArrayList<PendingSaveEntry>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val pw = obj.optString("password", "")
                if (pw.isEmpty()) continue
                list.add(
                    PendingSaveEntry(
                        title = obj.optString("title", ""),
                        username = obj.optString("username", ""),
                        password = pw,
                        domain = obj.optString("domain", ""),
                        packageName = obj.optString("packageName", ""),
                        capturedAt = obj.optLong("capturedAt", 0L),
                    )
                )
            }
            list
        } catch (_: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun clearAll(context: Context) {
        File(context.filesDir, VAULT_FILE).delete()
        File(context.filesDir, PENDING_SAVES_FILE).delete()
        try {
            val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            if (ks.containsAlias(KEY_ALIAS)) {
                ks.deleteEntry(KEY_ALIAS)
            }
        } catch (_: Exception) {
        }
    }

    fun normalizeDomain(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        var s = raw.trim().lowercase()
        if (s.contains("://")) {
            s = s.substringAfter("://")
        }
        s = s.substringBefore('/').substringBefore(':')
        if (s.startsWith("www.")) s = s.removePrefix("www.")
        if (s.startsWith("m.")) s = s.removePrefix("m.")
        return s
    }

    private fun domainsMatch(saved: String, target: String): Boolean {
        if (saved == target) return true
        if (target.endsWith(".$saved")) return true
        if (saved.endsWith(".$target")) return true
        return false
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGen.init(spec)
        return keyGen.generateKey()
    }

    private fun writeEncryptedFile(file: File, plaintext: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val plainBytes = plaintext.toByteArray(StandardCharsets.UTF_8)
        val ctAndTag = cipher.doFinal(plainBytes)
        plainBytes.fill(0)

        val out = ByteArray(iv.size + ctAndTag.size)
        System.arraycopy(iv, 0, out, 0, iv.size)
        System.arraycopy(ctAndTag, 0, out, iv.size, ctAndTag.size)
        file.writeBytes(out)
    }

    private fun readEncryptedFile(file: File): String? {
        if (!file.exists()) return null
        return try {
            val all = file.readBytes()
            if (all.size <= IV_SIZE + 16) return null
            val iv = all.copyOfRange(0, IV_SIZE)
            val ctAndTag = all.copyOfRange(IV_SIZE, all.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(),
                GCMParameterSpec(TAG_BITS, iv),
            )
            val plainBytes = cipher.doFinal(ctAndTag)
            val result = String(plainBytes, StandardCharsets.UTF_8)
            plainBytes.fill(0)
            result
        } catch (_: Exception) {
            null
        }
    }
}

