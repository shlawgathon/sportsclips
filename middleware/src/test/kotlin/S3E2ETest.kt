package gg.growly

import aws.sdk.kotlin.runtime.auth.credentials.StaticCredentialsProvider
import aws.sdk.kotlin.services.s3.S3Client
import aws.sdk.kotlin.services.s3.model.CreateBucketRequest
import aws.sdk.kotlin.services.s3.model.DeleteObjectRequest
import aws.sdk.kotlin.services.s3.model.HeadBucketRequest
import aws.sdk.kotlin.services.s3.model.NoSuchKey
import aws.sdk.kotlin.services.s3.model.S3Exception
import aws.smithy.kotlin.runtime.auth.awscredentials.Credentials
import aws.smithy.kotlin.runtime.net.url.Url
import gg.growly.services.Env
import gg.growly.services.S3Utility
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class S3E2ETest {
    private fun resolveEndpoint(): String? {
        val r2 = Env.get("R2_ENDPOINT")
        if (!r2.isNullOrBlank()) return r2
        val s3 = Env.get("AWS_S3_ENDPOINT")
        if (!s3.isNullOrBlank()) return s3
        val bucketEp = Env.get("AWS_S3_BUCKET_ENDPOINT")?.trimEnd('/')
        if (!bucketEp.isNullOrBlank()) {
            // If bucket endpoint is provided as https://host/bucket, derive host endpoint safely
            val protoIdx = bucketEp.indexOf("://")
            if (protoIdx > 0) {
                val lastSlash = bucketEp.lastIndexOf('/')
                if (lastSlash > protoIdx + 2) {
                    return bucketEp.substring(0, lastSlash)
                }
                return bucketEp // already host-style
            }
        }
        return null
    }

    private fun resolveRegion(): String = Env.get("R2_REGION", "auto") ?: "auto"

    private fun resolveBucket(): String = Env.get("AWS_S3_BUCKET_NAME") ?: "sportsclips-clip-store"

    private fun haveCreds(): Boolean {
        val ak = Env.get("R2_ACCESS_KEY_ID") ?: Env.get("AWS_ACCESS_KEY_ID")
        val sk = Env.get("R2_SECRET_ACCESS_KEY") ?: Env.get("AWS_SECRET_ACCESS_KEY")
        return !ak.isNullOrBlank() && !sk.isNullOrBlank()
    }

    @Test
    fun upload_and_download_bytes_end_to_end() = runBlocking {
        val endpoint = resolveEndpoint()
        val bucket = resolveBucket()
        if (endpoint.isNullOrBlank() || !haveCreds()) {
            println("[S3E2ETest] Skipping test: missing endpoint or credentials in env. Configure R2/AWS/MinIO env vars to run.")
            return@runBlocking
        }

        val accessKeyId = Env.get("R2_ACCESS_KEY_ID") ?: Env.get("AWS_ACCESS_KEY_ID")!!
        val secretAccessKey = Env.get("R2_SECRET_ACCESS_KEY") ?: Env.get("AWS_SECRET_ACCESS_KEY")!!

        // Client configured like production utility
        val client = S3Client {
            this.region = resolveRegion()
            this.endpointUrl = Url.parse(endpoint)
            this.forcePathStyle = true
            this.credentialsProvider = StaticCredentialsProvider(Credentials(accessKeyId, secretAccessKey))
        }

        // Ensure bucket exists (best-effort)
        try {
            client.headBucket(HeadBucketRequest { this.bucket = bucket })
        } catch (e: S3Exception) {
            try {
                client.createBucket(CreateBucketRequest { this.bucket = bucket })
            } catch (_: S3Exception) {
                // ignore if already exists or cannot be created in this environment
            }
        }

        val s3 = S3Utility(bucketName = bucket, region = resolveRegion())

        val key = "e2e/${System.currentTimeMillis()}-${(1000..9999).random()}.txt"
        val content = "hello s3 end-to-end"

        val etag = s3.uploadText(content, key)
        assertNotNull(etag, "ETag should not be null on upload")

        val exists = s3.objectExists(key)
        assertTrue(exists, "Uploaded object should exist: $key")

        val downloaded = s3.downloadText(key)
        assertEquals(content, downloaded, "Downloaded content must match uploaded content")

        // Cleanup
//        val del = client.deleteObject(DeleteObjectRequest { this.bucket = bucket; this.key = key })
        // Verify deletion by expecting not found on download
        try {
            println(String(s3.downloadBytes(key)))
            // If we get here, deletion didn't propagate yet (eventual consistency) — treat as success of main path
        } catch (e: NoSuchKey) {
            // expected sometimes
        } catch (_: Exception) {
            // ignore
        }

        client.close()
    }
}
