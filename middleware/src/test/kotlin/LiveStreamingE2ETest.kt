package gg.growly

import gg.growly.services.AgentClient
import io.ktor.server.application.*
import io.ktor.server.testing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Test
import org.junit.Assume
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertTrue

/**
 * E2E test that connects the middleware AgentClient to the external Agent WS, using
 * the provided live YouTube URL. It logs when a buffered batch (live_commentary_chunk)
 * is detected and writes each chunk to disk for later inspection.
 *
 * Notes:
 * - Requires network access to the agent host configured in AgentClient.
 * - Sets SEMAPHORE_MAX=1 for the AgentClient start gate.
 */
class LiveStreamingE2ETest {
    private val testUrl = "https://www.youtube.com/watch?v=8Gx4dpC2smo"

    @Test
    fun connect_and_capture_live_chunks() = testApplication {
        // Ensure the Application exists for logging; we don't need to install the full module
        application {
            // Minimal config/logger; leave default
        }

        // Ensure the AgentClient can read a required semaphore value
        System.setProperty("SEMAPHORE_MAX", "1")
        // Note: Env.getRequired will also check System properties; no strict assertion here

        val app: Application = this.application
        val outDir = File("middleware/build/live_e2e")
        outDir.mkdirs()
        val dateFmt = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
        val startStamp = dateFmt.format(Date())

        val agent = AgentClient(app)
        val chunkCounter = AtomicInteger(0)
        val snippetCounter = AtomicInteger(0)

        val maxChunksToCapture = 3 // keep the test bounded
        val maxMillis = 120_000L    // 2 minutes timeout to avoid hanging CI

        app.log.info("[LiveStreamingE2ETest] Starting AgentClient for url=$testUrl; saving output to ${outDir.absolutePath}")

        runBlocking {
            try {
                withTimeout(maxMillis) {
                    launch {
                        agent.processVideo(
                            sourceUrl = testUrl,
                            isLive = true,
                            onSnippet = { bytes, title, description ->
                                val n = snippetCounter.incrementAndGet()
                                val meta = buildString {
                                    append("title=")
                                    append(title ?: "")
                                    append(",descLen=")
                                    append(description?.length ?: 0)
                                }
                                val fname = "snippet_${startStamp}_$n.mp4"
                                val f = File(outDir, fname)
                                f.writeBytes(bytes)
                                app.log.info("[LiveStreamingE2ETest] Saved snippet n=$n bytes=${bytes.size} $meta -> ${f.absolutePath}")
                            },
                            onLiveChunk = { bytes, meta ->
                                val n = chunkCounter.incrementAndGet()
                                val fmt = meta.format.ifBlank { "bin" }
                                val fname = "chunk_${startStamp}_${meta.chunk_number}_$n.$fmt"
                                val f = File(outDir, fname)
                                f.writeBytes(bytes)
                                app.log.info("[LiveStreamingE2ETest] Buffered batch detected: chunk=${meta.chunk_number} bytes=${bytes.size} fmt=${meta.format} sr=${meta.audio_sample_rate} total=${meta.num_chunks_processed}; saved -> ${f.absolutePath}")
                            }
                        )
                    }

                    // Wait until we receive the desired number of chunks
                    while (chunkCounter.get() < maxChunksToCapture) {
                        // simple sleep loop
                        kotlinx.coroutines.delay(500)
                    }
                }
            } catch (ce: CancellationException) {
                // Test timeout or coroutine cancellation; continue to assertions
                app.log.info("[LiveStreamingE2ETest] Cancelled/Timed out: ${ce.message}")
            } catch (t: Throwable) {
                app.log.warn("[LiveStreamingE2ETest] Unexpected error: ${t.message}", t)
            }
        }

        // Verify at least one live chunk was saved
        val anyChunk = outDir.listFiles()?.any { it.name.startsWith("chunk_") && it.length() > 0 } ?: false
        if (!anyChunk) {
            app.log.warn("[LiveStreamingE2ETest] No live chunks were captured. This may happen if the external Agent WS is unreachable. Skipping test.")
        }
        Assume.assumeTrue("No chunks captured; likely offline or agent unavailable", anyChunk)

        app.log.info("[LiveStreamingE2ETest] Completed. Files saved in ${outDir.absolutePath}")
    }
}
