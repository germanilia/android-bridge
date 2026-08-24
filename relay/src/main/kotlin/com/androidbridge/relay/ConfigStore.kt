package com.androidbridge.relay

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.time.Clock
import kotlin.io.path.exists
import kotlin.io.path.readText

internal class ConfigStore(
    private val path: Path,
    setupCode: String,
    setupTtlSeconds: Long,
    clock: Clock,
) {
    private val json = Json { prettyPrint = true; encodeDefaults = true }
    private val mutex = Mutex()
    @Volatile private var current: RelayState = loadOrCreate(setupCode, setupTtlSeconds, clock)

    suspend fun update(transform: (RelayState) -> RelayState): RelayState = mutex.withLock {
        val updated = transform(current)
        persist(updated)
        current = updated
        updated
    }

    fun snapshot(): RelayState = current

    private fun loadOrCreate(setupCode: String, ttlSeconds: Long, clock: Clock): RelayState {
        if (path.exists()) return json.decodeFromString(path.readText())
        val setup = SetupState(TokenHasher.hash(setupCode), clock.instant().epochSecond + ttlSeconds)
        return RelayState(setup = setup).also(::persist)
    }

    private fun persist(state: RelayState) {
        Files.createDirectories(path.toAbsolutePath().parent)
        val temporary = path.resolveSibling("${path.fileName}.tmp")
        Files.writeString(temporary, json.encodeToString(state))
        try {
            Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING)
        }
    }
}
