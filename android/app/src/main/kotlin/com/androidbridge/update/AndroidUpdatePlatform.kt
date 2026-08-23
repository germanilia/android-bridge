package com.androidbridge.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class VerifiedApk internal constructor(internal val file: File)

class ApkSignatureVerifier(private val context: Context) {
    fun verify(download: DownloadedApk, expected: String): VerifiedApk = try {
        val installed = signer(packageInfo())
        val archive = signer(archiveInfo(download.file))
        if (installed != archive || archive != expected) throw AndroidUpdateException.Signature
        VerifiedApk(download.file)
    } catch (error: AndroidUpdateException) {
        throw error
    } catch (_: PackageManager.NameNotFoundException) {
        throw AndroidUpdateException.Signature
    } catch (_: SecurityException) {
        throw AndroidUpdateException.Signature
    } catch (_: RuntimeException) {
        throw AndroidUpdateException.Signature
    }

    private fun packageInfo() = context.packageManager.getPackageInfo(
        context.packageName,
        PackageManager.GET_SIGNING_CERTIFICATES,
    )

    private fun archiveInfo(file: File) = context.packageManager.getPackageArchiveInfo(
        file.path,
        PackageManager.GET_SIGNING_CERTIFICATES,
    ) ?: throw AndroidUpdateException.Signature

    private fun signer(info: android.content.pm.PackageInfo): String {
        val signers = info.signingInfo?.apkContentsSigners ?: throw AndroidUpdateException.Signature
        if (signers.size != 1) throw AndroidUpdateException.Signature
        return fingerprint(signers.single().toByteArray())
    }

    private fun fingerprint(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }
}

class ApkInstaller(private val context: Context) {
    fun install(apk: VerifiedApk) {
        val uri = try {
            FileProvider.getUriForFile(context, "${context.packageName}.updates", apk.file)
        } catch (_: IllegalArgumentException) {
            throw AndroidUpdateException.Installer
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}

sealed interface AndroidUpdateUiState {
    data object Idle : AndroidUpdateUiState
    data class Checking(val manual: Boolean) : AndroidUpdateUiState
    data class Available(val update: AndroidUpdate) : AndroidUpdateUiState
    data object Downloading : AndroidUpdateUiState
    data object InstallerLaunched : AndroidUpdateUiState
    data class Error(val message: String) : AndroidUpdateUiState
    data object UpToDate : AndroidUpdateUiState
}

class AndroidUpdateCoordinator(
    private val context: Context,
    private val service: AndroidUpdateService = productionService(context),
    private val verifier: ApkSignatureVerifier = ApkSignatureVerifier(context),
    private val installer: ApkInstaller = ApkInstaller(context),
) {
    private val mutableState = MutableStateFlow<AndroidUpdateUiState>(AndroidUpdateUiState.Idle)
    private var automaticStarted = false
    val state: StateFlow<AndroidUpdateUiState> = mutableState.asStateFlow()

    suspend fun check(manual: Boolean) {
        if (!manual && automaticStarted) return
        if (!manual) automaticStarted = true
        mutableState.value = AndroidUpdateUiState.Checking(manual)
        try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionName = packageInfo.versionName ?: throw AndroidUpdateException.InvalidVersion
            val update = service.check(versionName, packageInfo.longVersionCode.toInt())
            mutableState.value = if (update == null) AndroidUpdateUiState.UpToDate else AndroidUpdateUiState.Available(update)
        } catch (error: AndroidUpdateException) {
            mutableState.value = if (manual) AndroidUpdateUiState.Error(error.message!!) else AndroidUpdateUiState.Idle
        }
    }

    suspend fun downloadAndInstall(update: AndroidUpdate) {
        mutableState.value = AndroidUpdateUiState.Downloading
        try {
            installDownloaded(service.downloadAndVerify(update), update)
            mutableState.value = AndroidUpdateUiState.InstallerLaunched
        } catch (error: AndroidUpdateException) {
            mutableState.value = AndroidUpdateUiState.Error(error.message!!)
        }
    }

    private fun installDownloaded(downloaded: DownloadedApk, update: AndroidUpdate) {
        try {
            installer.install(verifier.verify(downloaded, update.bundle.signerSha256))
        } catch (error: AndroidUpdateException) {
            service.remove(downloaded)
            throw error
        } catch (_: android.content.ActivityNotFoundException) {
            service.remove(downloaded)
            throw AndroidUpdateException.Installer
        } catch (_: SecurityException) {
            service.remove(downloaded)
            throw AndroidUpdateException.Installer
        }
    }

    fun dismiss() { mutableState.value = AndroidUpdateUiState.Idle }
    fun cancel() { mutableState.value = AndroidUpdateUiState.Idle }
    fun cleanStale(): Boolean = try {
        service.cleanTemporaryUpdates()
        true
    } catch (error: AndroidUpdateException) {
        mutableState.value = AndroidUpdateUiState.Error(error.message!!)
        false
    }

    companion object {
        private fun productionService(context: Context): AndroidUpdateService {
            val root = File(context.cacheDir, "updates")
            if (!root.exists() && !root.mkdirs()) throw AndroidUpdateException.Storage
            return AndroidUpdateService(GitHubReleaseSource(), HttpArtifactDownloader(), root)
        }
    }
}
