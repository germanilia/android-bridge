package com.androidbridge.core

/** A feature plugin id (matches the per-feature toggle in Settings — U10). */
enum class FeatureId { NOTIFICATIONS, SMS, FILES, CLIPBOARD, SCREEN, CALLS }

/**
 * Tracks which feature plugins are enabled (FR-9.2). Default: all enabled; the Settings unit
 * persists overrides. Pure logic — JVM-testable.
 */
class PluginRegistry(enabledByDefault: Set<FeatureId> = FeatureId.values().toSet()) {
    private val enabled = enabledByDefault.toMutableSet()

    fun enable(id: FeatureId) { enabled.add(id) }
    fun disable(id: FeatureId) { enabled.remove(id) }
    fun isEnabled(id: FeatureId): Boolean = id in enabled
    fun enabled(): Set<FeatureId> = enabled.toSet()
}
