package com.androidbridge.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile

data class SecondBrainNode(val path: String, val label: String, val isDirectory: Boolean, val depth: Int, val modifiedAt: Long = 0)

/**
 * Second Brain notes backed by a user-granted Syncthing folder (SAF tree URI).
 * Syncthing keeps the folder in sync with the Mac and the home server; this class
 * only reads and writes the local markdown tree — there is no device-to-device sync here.
 */
class SecondBrainFolder(private val context: Context) {
    private val prefs = context.getSharedPreferences("second-brain", Context.MODE_PRIVATE)
    private val resolver get() = context.contentResolver

    fun hasFolder(): Boolean = root()?.isDirectory == true

    fun folderName(): String = root()?.name ?: ""

    fun setFolder(uri: Uri) {
        resolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        prefs.edit().putString(KEY_TREE_URI, uri.toString()).apply()
    }

    fun nodes(): List<SecondBrainNode> {
        val root = root() ?: return emptyList()
        val out = mutableListOf<SecondBrainNode>()
        walk(root, "", 0, out)
        // Lexicographic path sort yields correct tree pre-order (folder before its contents).
        return out.sortedBy { it.path }
    }

    fun content(path: String): String {
        val file = resolve(path) ?: return ""
        return resolver.openInputStream(file.uri)?.use { it.readBytes().decodeToString() } ?: ""
    }

    fun save(path: String, content: String) {
        require(isMarkdownPath(path)) { "Only .md notes are supported" }
        val root = root() ?: return
        val segments = path.split('/')
        var dir = root
        for (seg in segments.dropLast(1)) {
            dir = dir.findFile(seg)?.takeIf { it.isDirectory } ?: dir.createDirectory(seg) ?: return
        }
        val name = segments.last()
        val file = dir.findFile(name) ?: dir.createFile("text/markdown", name) ?: return
        resolver.openOutputStream(file.uri, "wt")?.use { it.write(content.toByteArray()) }
    }

    fun delete(path: String) {
        resolve(path)?.delete()
    }

    fun search(query: String): List<SecondBrainNode> {
        val terms = query.lowercase().split(Regex("\\s+")).filter { it.isNotBlank() }
        val files = nodes().filterNot { it.isDirectory }
        if (terms.isEmpty()) return files.take(30)
        return files.filter { node ->
            val haystack = (node.path + "\n" + content(node.path)).lowercase()
            terms.all { haystack.contains(it) }
        }.take(30)
    }

    private fun root(): DocumentFile? =
        prefs.getString(KEY_TREE_URI, null)?.let { DocumentFile.fromTreeUri(context, Uri.parse(it)) }

    private fun walk(dir: DocumentFile, prefix: String, depth: Int, out: MutableList<SecondBrainNode>) {
        for (child in dir.listFiles()) {
            val name = child.name ?: continue
            if (name.startsWith(".")) continue
            val path = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.isDirectory) {
                out.add(SecondBrainNode(path, name, true, depth, child.lastModified()))
                walk(child, path, depth + 1, out)
            } else if (name.endsWith(".md")) {
                out.add(SecondBrainNode(path, name, false, depth, child.lastModified()))
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
