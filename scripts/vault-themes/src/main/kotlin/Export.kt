import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import team.sopa.boar.ui.theme.BoarColors
import team.sopa.boar.ui.theme.Themes

// Every Vault theme (ExtraThemes.kt) as JSON: id, name, icon, light and each color token as #AARRGGBB, computed by
// Compose's own Color and lerp (Oklab), the same code the Android app runs.
fun main() {
    val getters = BoarColors::class.java.declaredMethods
        .filter { it.name.startsWith("get") && it.parameterCount == 0 && it.returnType == java.lang.Long.TYPE }
        .sortedBy { it.name }
    val themes = Themes.extras.joinToString(",\n") { t ->
        val colors = getters.joinToString(", ") { m ->
            val name = m.name.removePrefix("get").substringBefore('-').replaceFirstChar { it.lowercase() }
            val argb = Color((m.invoke(t) as Long).toULong()).toArgb()
            "\"$name\": \"#%08X\"".format(argb)
        }
        "  {\"id\": \"${t.id}\", \"name\": \"${t.name}\", \"icon\": \"${t.icon}\", \"light\": ${t.light}, \"colors\": {$colors}}"
    }
    println("[\n$themes\n]")
}
