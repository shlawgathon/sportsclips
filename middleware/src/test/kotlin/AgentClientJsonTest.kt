package gg.growly

import gg.growly.services.AgentClient
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

class AgentClientJsonTest {
    @Test
    fun liveChunkMeta_decodes_with_extra_fields_ignored() {
        val json = Json { ignoreUnknownKeys = true }
        val metaJson = """
            {
              "src_video_url": "https://example.com/live",
              "chunk_number": 5,
              "format": "mp4",
              "audio_sample_rate": 44100,
              "commentary_length_bytes": 12345,
              "video_length_bytes": 67890,
              "num_chunks_processed": 7,
              "base_chunks_combined": 3,
              "audio_chunks_count": 22,
              "audio_bytes": 243840
            }
        """.trimIndent()

        val meta = json.decodeFromString(AgentClient.LiveChunkMeta.serializer(), metaJson)
        assertEquals("https://example.com/live", meta.src_video_url)
        assertEquals(5, meta.chunk_number)
        assertEquals("mp4", meta.format)
        assertEquals(44100, meta.audio_sample_rate)
        assertEquals(12345, meta.commentary_length_bytes)
        assertEquals(67890, meta.video_length_bytes)
        assertEquals(7, meta.num_chunks_processed)
    }
}
