package gg.growly.services

import io.ktor.server.application.Application
import io.ktor.server.config.tryGetString

/**
 * Minimal helper to return upload and download URLs for storing clips in S3-compatible storage.
 *
 * This is a lightweight implementation that avoids extra SDK dependencies. It constructs
 * HTTPS URLs using configuration values. If you need true pre-signed URLs with temporary
 * credentials, this helper can be upgraded later to use AWS SDK's S3Presigner.
 */
class S3Helper(application: Application) {
    private val bucket: String = "sportsclips-clip-store"
    private val region: String = "us-east-1"
    private val endpoint: String = Env.getRequired("AWS_S3_BUCKET_ENDPOINT")

    private fun normalize(base: String): String = base.trimEnd('/')

    private fun buildUrlForKey(key: String): String {
        val base = normalize(endpoint)
        // If endpoint already includes the bucket, just append the key
        return when {
            "{bucket}" in base -> base.replace("{bucket}", bucket) + "/" + key.trimStart('/')
            base.contains("://$bucket.") -> "$base/" + key.trimStart('/')
            else -> "$base/$bucket/" + key.trimStart('/')
        }
    }

    /**
     * Returns a URL where the client can PUT the clip bytes. This is not a cryptographically
     * signed URL; it assumes your bucket policy or gateway handles auth. Replace with an
     * actual presign implementation if needed.
     */
    fun presignUpload(key: String, contentType: String? = null): String {
        // contentType is unused in this minimal implementation
        return buildUrlForKey(key)
    }

    /**
     * Returns a direct HTTPS URL that can be used to GET the clip bytes.
     */
    fun directDownloadUrl(key: String): String = buildUrlForKey(key)
}
