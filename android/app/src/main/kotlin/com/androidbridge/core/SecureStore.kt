package com.androidbridge.core

/**
 * Encrypted key-value persistence for trust material and sensitive settings (SECURITY-01/-12).
 * The Android implementation is backed by Keystore + EncryptedSharedPreferences; an in-memory
 * implementation is used for pure unit tests.
 */
interface SecureStore {
    fun put(key: String, value: String)
    fun get(key: String): String?
    fun delete(key: String)
}

/** In-memory store for tests and non-persistent contexts. */
class InMemorySecureStore : SecureStore {
    private val map = HashMap<String, String>()
    override fun put(key: String, value: String) { map[key] = value }
    override fun get(key: String): String? = map[key]
    override fun delete(key: String) { map.remove(key) }
}
