package com.androidbridge.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

data class SecondBrainNode(val path: String, val label: String, val isDirectory: Boolean, val depth: Int, val modifiedAt: Long = 0)

/** A search match: the note plus a content line that matched, for context. */
data class SecondBrainHit(val node: SecondBrainNode, val snippet: String)

/** One pass over the folder: visible notes and Syncthing conflict copies. */
data class BrainScan(val nodes: List<SecondBrainNode>, val conflicts: List<SecondBrainNode>)

/**
 * Second Brain notes backed by a user-granted Syncthing folder (SAF tree URI).
 * Syncthing keeps the folder in sync with the Mac and the home server; this class
 * only reads and writes the local markdown tree — there is no device-to-device sync here.
 */
class SecondBrainFolder(private val context: Context) : BrainSyncStorage {
    private val prefs = context.getSharedPreferences("second-brain", Context.MODE_PRIVATE)
    private val resolver get() = context.contentResolver
    // SAF reads are slow; cache note contents keyed by (path, lastModified).
    private val contentCache = ConcurrentHashMap<String, Pair<Long, String>>()

    fun hasFolder(): Boolean = root()?.isDirectory == true

    fun folderName(): String = root()?.name ?: ""

    fun setFolder(uri: Uri) {
        resolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        prefs.edit().putString(KEY_TREE_URI, uri.toString()).apply()
    }

    fun scan(): BrainScan {
        val root = root() ?: return BrainScan(emptyList(), emptyList())
        contentCache.clear()
        val all = mutableListOf<SecondBrainNode>()
        walk(root, "", 0, all)
        val (conflicts, nodes) = all.partition { !it.isDirectory && isSyncConflictPath(it.path) }
        return BrainScan(nodes, conflicts)
    }

    fun nodes(): List<SecondBrainNode> = scan().nodes

    fun content(path: String): String {
        val file = resolve(path) ?: throw FileNotFoundException("Note not found: $path")
        val stamp = file.lastModified()
        contentCache[path]?.let { (cachedStamp, text) -> if (cachedStamp == stamp) return text }
        val text = resolver.openInputStream(file.uri)?.use { it.readBytes().decodeToString() }
            ?: throw IOException("Cannot read note: $path")
        contentCache[path] = stamp to text
        return text
    }

    fun save(path: String, content: String) {
        require(isMarkdownPath(path)) { "Only .md notes are supported" }
        write(path, content.encodeToByteArray())
    }

    override fun files(): List<BrainSyncFile> {
        val folder = root() ?: return emptyList()
        val files = mutableListOf<BrainSyncFile>()
        walkSyncFiles(folder, "", files)
        return files
    }

    override fun read(path: String): ByteArray? {
        require(BrainSyncPolicy.allowsTombstone(path)) { "Unsupported sync path" }
        val file = resolve(path) ?: return null
        return resolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw IOException("Cannot read sync file: $path")
    }

    override fun write(path: String, bytes: ByteArray) {
        val mediaType = requireNotNull(BrainSyncPolicy.writableMediaType(path, bytes)) { "Unsupported sync content" }
        val segments = path.split('/')
        var directory = root() ?: throw IOException("Second Brain folder is unavailable")
        for (segment in segments.dropLast(1)) {
            directory = directory.findFile(segment)?.takeIf { it.isDirectory }
                ?: directory.createDirectory(segment)
                ?: throw IOException("Cannot create folder: $segment")
        }
        val name = segments.last()
        val file = directory.findFile(name) ?: directory.createFile(mediaType, name)
            ?: throw IOException("Cannot create sync file: $name")
        resolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw IOException("Cannot write sync file: $name")
        contentCache.remove(path)
    }

    override fun delete(path: String) {
        val file = resolve(path) ?: throw FileNotFoundException("Note not found: $path")
        if (!file.delete()) throw IOException("Cannot delete note: $path")
        contentCache.remove(path)
    }

    /**
     * Deletes every Syncthing conflict copy, accepting the synced winner file.
     * Returns how many copies were removed.
     */
    fun deleteConflicts(): Int {
        val conflicts = scan().conflicts
        conflicts.forEach { delete(it.path) }
        return conflicts.size
    }

    /**
     * AND-matches whitespace-separated terms. Terms starting with `#` match the
     * note's frontmatter tags; other terms match path + content. Title matches
     * rank first, then most recently modified.
     */
    fun search(query: String): List<SecondBrainHit> {
        val rawTerms = query.split(Regex("\\s+")).filter { it.isNotBlank() }
        val files = scan().nodes.filterNot { it.isDirectory }
        if (rawTerms.isEmpty()) {
            return files.sortedByDescending { it.modifiedAt }.take(30).map { SecondBrainHit(it, "") }
        }
        val tagTerms = rawTerms.filter { it.startsWith("#") && it.length > 1 }.map { it.drop(1).lowercase() }
        val textTerms = rawTerms.filterNot { it.startsWith("#") }.map { it.lowercase() }
        return files.mapNotNull { node ->
            val body = content(node.path)
            val tags = parseNoteTags(body).map { it.lowercase() }
            if (!tagTerms.all { tag -> tags.any { it.contains(tag) } }) return@mapNotNull null
            val haystack = (node.path + "\n" + body).lowercase()
            if (!textTerms.all { haystack.contains(it) }) return@mapNotNull null
            SecondBrainHit(node, searchSnippet(body, textTerms.ifEmpty { tagTerms }))
        }
            .sortedWith(
                compareByDescending<SecondBrainHit> { hit -> textTerms.any { hit.node.label.lowercase().contains(it) } }
                    .thenByDescending { it.node.modifiedAt },
            )
            .take(30)
    }

    private fun root(): DocumentFile? =
        prefs.getString(KEY_TREE_URI, null)?.let { DocumentFile.fromTreeUri(context, Uri.parse(it)) }

    private fun walk(dir: DocumentFile, prefix: String, depth: Int, out: MutableList<SecondBrainNode>) {
        // Folders first, then notes, both alphabetical — the emitted pre-order is
        // exactly the drawer's display order.
        val children = dir.listFiles()
            .mapNotNull { child -> child.name?.let { it to child } }
            .filterNot { (name, _) -> name.startsWith(".") }
            .sortedWith(compareBy({ !it.second.isDirectory }, { it.first.lowercase() }))
        for ((name, child) in children) {
            val path = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.isDirectory) {
                out.add(SecondBrainNode(path, name, true, depth, child.lastModified()))
                walk(child, path, depth + 1, out)
            } else if (name.endsWith(".md")) {
                out.add(SecondBrainNode(path, name, false, depth, child.lastModified()))
            }
        }
    }

    private fun walkSyncFiles(directory: DocumentFile, prefix: String, output: MutableList<BrainSyncFile>) {
        for (child in directory.listFiles()) {
            val name = child.name ?: continue
            if (name.startsWith(".")) continue
            val path = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.isDirectory) {
                walkSyncFiles(child, path, output)
            } else if (BrainSyncPolicy.allowsTombstone(path) && !isSyncConflictPath(path)) {
                val bytes = resolver.openInputStream(child.uri)?.use { it.readBytes() }
                    ?: throw IOException("Cannot read sync file: $path")
                output += BrainSyncFile(path, bytes)
            }
        }
    }

    private fun resolve(path: String): DocumentFile? {
        var doc = root() ?: return null
        for (seg in path.split('/')) {
            doc = doc.findFile(seg) ?: return null
        }
        return doc
    }

    companion object {
        private const val KEY_TREE_URI = "treeUri"
        fun isMarkdownPath(path: String): Boolean =
            path.endsWith(".md") && !path.contains("..") && !path.startsWith("/")
    }
}
