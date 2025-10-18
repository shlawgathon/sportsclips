import java.io.BufferedReader
import java.io.FileReader
import java.io.IOException

/**
 * @author Subham
 * @since 10/11/25
 */
object LoadEnvUtility
{
    private fun loadFromPath(path: String) {
        try {
            BufferedReader(FileReader(path)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val trimmed = line!!.trim { it <= ' ' }
                    if (trimmed.isNotEmpty() && !trimmed.startsWith("#")) {
                        val parts: Array<String?> = trimmed.split("=", limit = 2).toTypedArray()
                        if (parts.size == 2) {
                            val key = parts[0]!!.trim { it <= ' ' }
                            val value = parts[1]!!.trim { it <= ' ' }
                            System.setProperty(key, value)
                        }
                    }
                }
            }
            println("[DEBUG_LOG] Loaded environment variables from $path")
        } catch (e: IOException) {
            // Silently ignore; we'll try other locations.
            println("[DEBUG_LOG] Could not load env from $path: ${e.message}")
        }
    }

    fun loadEnv()
    {
        // Try common locations
        loadFromPath(".env")
        loadFromPath("middleware/.env")
    }
}
