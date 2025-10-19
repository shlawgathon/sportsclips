
package gg.growly.services

import aws.sdk.kotlin.services.s3.S3Client
import aws.sdk.kotlin.services.s3.model.*
import aws.sdk.kotlin.runtime.auth.credentials.StaticCredentialsProvider
import aws.sdk.kotlin.services.s3.presigners.presignGetObject
import aws.smithy.kotlin.runtime.auth.awscredentials.Credentials
import aws.smithy.kotlin.runtime.content.ByteStream
import aws.smithy.kotlin.runtime.content.toByteArray
import aws.smithy.kotlin.runtime.net.url.Url
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.nio.file.Path
import kotlin.io.path.readBytes
import kotlin.io.path.writeBytes
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours

/**
 * Utility class for common S3 operations using AWS SDK for Kotlin
 *
 * @property bucketName The default S3 bucket name to use for operations
 * @property region The AWS region (optional, uses default if not specified)
 */
class S3Utility(
    private val bucketName: String,
    private val region: String? = null
) {
    private val s3Client: S3Client by lazy {
        fun deriveEndpoint(): String? {
            val r2 = Env.get("R2_ENDPOINT")
            if (!r2.isNullOrBlank()) return r2
            val s3 = Env.get("AWS_S3_ENDPOINT")
            if (!s3.isNullOrBlank()) return s3
            val bucketEp = Env.get("AWS_S3_BUCKET_ENDPOINT")?.trimEnd('/')
            if (!bucketEp.isNullOrBlank()) {
                val protoIdx = bucketEp.indexOf("://")
                if (protoIdx > 0) {
                    val lastSlash = bucketEp.lastIndexOf('/')
                    return if (lastSlash > protoIdx + 2) bucketEp.substring(0, lastSlash) else bucketEp
                }
            }
            return null
        }

        val endpoint = deriveEndpoint()
        val accessKeyId = Env.get("R2_ACCESS_KEY_ID") ?: Env.get("AWS_ACCESS_KEY_ID")
        val secretAccessKey = Env.get("R2_SECRET_ACCESS_KEY") ?: Env.get("AWS_SECRET_ACCESS_KEY")
        val r2Region = Env.get("R2_REGION", "auto")

        S3Client {
            // Cloudflare R2 prefers region "auto"
            this.region = r2Region ?: region ?: "auto"
            endpoint?.let { this.endpointUrl = Url.parse(it) }
            // Path-style is required for R2
            this.forcePathStyle = true
            if (!accessKeyId.isNullOrBlank() && !secretAccessKey.isNullOrBlank()) {
                this.credentialsProvider = StaticCredentialsProvider(Credentials(accessKeyId, secretAccessKey))
            }
        }
    }

    /**
     * Upload a file to S3
     *
     * @param localFilePath Path to the local file
     * @param s3Key The key (path) where the file will be stored in S3
     * @param contentType Optional MIME type of the file
     * @param metadata Optional metadata to attach to the object
     * @return The ETag of the uploaded object
     */
    suspend fun uploadFile(
        localFilePath: Path,
        s3Key: String,
        contentType: String? = null,
        metadata: Map<String, String>? = null
    ): String? {
        val fileBytes = localFilePath.readBytes()

        val request = PutObjectRequest {
            bucket = bucketName
            key = s3Key
            body = ByteStream.fromBytes(fileBytes)
            contentType?.let { this.contentType = it }
            metadata?.let { this.metadata = it }
        }

        val response = s3Client.putObject(request)
        return response.eTag
    }

    /**
     * Upload bytes directly to S3
     *
     * @param data The byte array to upload
     * @param s3Key The key (path) where the data will be stored in S3
     * @param contentType Optional MIME type
     * @param metadata Optional metadata to attach to the object
     * @return The ETag of the uploaded object
     */
    suspend fun uploadBytes(
        data: ByteArray,
        s3Key: String,
        contentType: String? = null,
        metadata: Map<String, String>? = null
    ): String? {
        val request = PutObjectRequest {
            bucket = bucketName
            key = s3Key
            body = ByteStream.fromBytes(data)
            contentType?.let { this.contentType = it }
            metadata?.let { this.metadata = it }
        }

        val response = s3Client.putObject(request)
        return response.eTag
    }

    /**
     * Upload a string as text to S3
     *
     * @param content The string content to upload
     * @param s3Key The key (path) where the content will be stored in S3
     * @param metadata Optional metadata to attach to the object
     * @return The ETag of the uploaded object
     */
    suspend fun uploadText(
        content: String,
        s3Key: String,
        metadata: Map<String, String>? = null
    ): String? {
        return uploadBytes(
            data = content.toByteArray(),
            s3Key = s3Key,
            contentType = "text/plain; charset=UTF-8",
            metadata = metadata
        )
    }

    /**
     * Download a file from S3 to local filesystem
     *
     * @param s3Key The key (path) of the object in S3
     * @param localFilePath Path where the file will be saved locally
     * @return The downloaded file metadata
     */
    suspend fun downloadFile(
        s3Key: String,
        localFilePath: Path
    ): S3FileMetadata {
        val request = GetObjectRequest {
            bucket = bucketName
            key = s3Key
        }

        val response = s3Client.getObject(request) { resp ->
            val bytes = resp.body?.toByteArray() ?: ByteArray(0)
            localFilePath.writeBytes(bytes)

            S3FileMetadata(
                key = s3Key,
                contentType = resp.contentType,
                contentLength = resp.contentLength,
                lastModified = resp.lastModified,
                eTag = resp.eTag,
                metadata = resp.metadata
            )
        }

        return response
    }

    /**
     * Download an object from S3 as bytes
     *
     * @param s3Key The key (path) of the object in S3
     * @return The object content as byte array
     */
    suspend fun downloadBytes(s3Key: String): ByteArray {
        val request = GetObjectRequest {
            bucket = bucketName
            key = s3Key
        }

        return s3Client.getObject(request) { resp ->
            resp.body?.toByteArray() ?: ByteArray(0)
        }
    }

    /**
     * Download an object from S3 as string
     *
     * @param s3Key The key (path) of the object in S3
     * @return The object content as string
     */
    suspend fun downloadText(s3Key: String): String {
        val bytes = downloadBytes(s3Key)
        return String(bytes, Charsets.UTF_8)
    }

    /**
     * Check if an object exists in S3
     *
     * @param s3Key The key (path) of the object to check
     * @return True if the object exists, false otherwise
     */
    suspend fun objectExists(s3Key: String): Boolean {
        return try {
            val request = HeadObjectRequest {
                bucket = bucketName
                key = s3Key
            }
            s3Client.headObject(request)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Delete an object from S3
     *
     * @param s3Key The key (path) of the object to delete
     * @return True if deletion was successful
     */
    suspend fun deleteObject(s3Key: String): Boolean {
        return try {
            val request = DeleteObjectRequest {
                bucket = bucketName
                key = s3Key
            }
            s3Client.deleteObject(request)
            true
        } catch (e: Exception) {
            false
        }
    }

    suspend fun generatePresignedGetUrl(
        s3Key: String,
        expiration: Duration = 1.hours,
        responseContentType: String? = null,
        responseContentDisposition: String? = null
    ): String {
        val request = GetObjectRequest {
            bucket = bucketName
            key = s3Key
            responseContentType?.let { this.responseContentType = it }
            responseContentDisposition?.let { this.responseContentDisposition = it }
        }

        val presignRequest = s3Client.presignGetObject(request, expiration)
        return presignRequest.url.toString()
    }

    /**
     * Delete multiple objects from S3
     *
     * @param s3Keys List of keys to delete
     * @return List of successfully deleted keys
     */
    suspend fun deleteObjects(s3Keys: List<String>): List<String> {
        if (s3Keys.isEmpty()) return emptyList()

        val objectsToDelete = s3Keys.map { key ->
            ObjectIdentifier {
                this.key = key
            }
        }

        val request = DeleteObjectsRequest {
            bucket = bucketName
            delete = Delete {
                objects = objectsToDelete
            }
        }

        val response = s3Client.deleteObjects(request)
        return response.deleted?.mapNotNull { it.key } ?: emptyList()
    }

    /**
     * List objects in S3 bucket with optional prefix
     *
     * @param prefix Optional prefix to filter objects
     * @param maxKeys Maximum number of keys to return (default 1000)
     * @return List of S3 object summaries
     */
    suspend fun listObjects(
        prefix: String? = null,
        maxKeys: Int = 1000
    ): List<S3ObjectSummary> {
        val request = ListObjectsV2Request {
            bucket = bucketName
            prefix?.let { this.prefix = it }
            this.maxKeys = maxKeys
        }

        val response = s3Client.listObjectsV2(request)
        return response.contents?.map { obj ->
            S3ObjectSummary(
                key = obj.key ?: "",
                size = obj.size,
                lastModified = obj.lastModified,
                eTag = obj.eTag,
                storageClass = obj.storageClass?.value
            )
        } ?: emptyList()
    }

    /**
     * List all objects with pagination support
     *
     * @param prefix Optional prefix to filter objects
     * @return Flow of S3 object summaries
     */
    fun listObjectsPaginated(prefix: String? = null): Flow<S3ObjectSummary> = flow {
        var continuationToken: String? = null

        do {
            val request = ListObjectsV2Request {
                bucket = bucketName
                prefix?.let { this.prefix = it }
                continuationToken?.let { this.continuationToken = it }
                maxKeys = 1000
            }

            val response = s3Client.listObjectsV2(request)

            response.contents?.forEach { obj ->
                emit(
                    S3ObjectSummary(
                        key = obj.key ?: "",
                        size = obj.size,
                        lastModified = obj.lastModified,
                        eTag = obj.eTag,
                        storageClass = obj.storageClass?.value
                    )
                )
            }

            continuationToken = response.nextContinuationToken
        } while (response.isTruncated == true)
    }

    /**
     * Get object metadata without downloading the object
     *
     * @param s3Key The key of the object
     * @return Object metadata or null if object doesn't exist
     */
    suspend fun getObjectMetadata(s3Key: String): S3FileMetadata? {
        return try {
            val request = HeadObjectRequest {
                bucket = bucketName
                key = s3Key
            }

            val response = s3Client.headObject(request)
            S3FileMetadata(
                key = s3Key,
                contentType = response.contentType,
                contentLength = response.contentLength,
                lastModified = response.lastModified,
                eTag = response.eTag,
                metadata = response.metadata
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Create a multipart upload for large files
     *
     * @param localFilePath Path to the large file
     * @param s3Key The key where the file will be stored
     * @param partSize Size of each part in bytes (default 5MB)
     * @return The ETag of the uploaded object
     */
    suspend fun multipartUpload(
        localFilePath: Path,
        s3Key: String,
        partSize: Long = 5 * 1024 * 1024 // 5MB default
    ): String? {
        val file = localFilePath.toFile()
        val fileSize = file.length()

        // Initiate multipart upload
        val initiateRequest = CreateMultipartUploadRequest {
            bucket = bucketName
            key = s3Key
        }

        val initiateResponse = s3Client.createMultipartUpload(initiateRequest)
        val uploadId = initiateResponse.uploadId

        try {
            val parts = mutableListOf<CompletedPart>()
            var partNumber = 1
            var position = 0L

            // Upload parts
            while (position < fileSize) {
                val currentPartSize = minOf(partSize, fileSize - position)
                val buffer = ByteArray(currentPartSize.toInt())

                file.inputStream().use { input ->
                    input.skip(position)
                    input.read(buffer)
                }

                val uploadRequest = UploadPartRequest {
                    bucket = bucketName
                    key = s3Key
                    this.uploadId = uploadId
                    this.partNumber = partNumber
                    body = ByteStream.fromBytes(buffer)
                }

                val uploadResponse = s3Client.uploadPart(uploadRequest)

                parts.add(CompletedPart {
                    this.partNumber = partNumber
                    eTag = uploadResponse.eTag
                })

                position += currentPartSize
                partNumber++
            }

            // Complete multipart upload
            val completeRequest = CompleteMultipartUploadRequest {
                bucket = bucketName
                key = s3Key
                this.uploadId = uploadId
                multipartUpload = CompletedMultipartUpload {
                    this.parts = parts
                }
            }

            val completeResponse = s3Client.completeMultipartUpload(completeRequest)
            return completeResponse.eTag

        } catch (e: Exception) {
            // Abort multipart upload on failure
            val abortRequest = AbortMultipartUploadRequest {
                bucket = bucketName
                key = s3Key
                this.uploadId = uploadId
            }
            s3Client.abortMultipartUpload(abortRequest)
            throw e
        }
    }

    /**
     * Close the S3 client
     */
    fun close() {
        s3Client.close()
    }
}

/**
 * Data class for S3 file metadata
 */
data class S3FileMetadata(
    val key: String,
    val contentType: String?,
    val contentLength: Long?,
    val lastModified: aws.smithy.kotlin.runtime.time.Instant?,
    val eTag: String?,
    val metadata: Map<String, String>?
)

/**
 * Data class for S3 object summary
 */
data class S3ObjectSummary(
    val key: String,
    val size: Long?,
    val lastModified: aws.smithy.kotlin.runtime.time.Instant?,
    val eTag: String?,
    val storageClass: String?
)

/**
 * HTTP methods for presigned URLs
 */
enum class HttpMethod {
    GET, PUT, POST, DELETE, HEAD
}
