package com.contactlogo.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Slate900 = Color(0xFF0F172A)
val Slate800 = Color(0xFF1E293B)
val Slate700 = Color(0xFF334155)
val Slate100 = Color(0xFFF1F5F9)
val Sky500 = Color(0xFF0EA5E9)
val Sky400 = Color(0xFF38BDF8)
val Green500 = Color(0xFF22C55E)
val Amber500 = Color(0xFFF59E0B)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF7DD3FC),
    onPrimary = Color(0xFF082F49),
    secondary = Color(0xFF86EFAC),
    onSecondary = Color(0xFF052E16),
    tertiary = Color(0xFFFDBA74),
    onTertiary = Color(0xFF431407),
    background = Color(0xFF0C0A09),
    surface = Color(0xFF1C1917),
    onBackground = Color(0xFFF2F2F7),
    onSurface = Color(0xFFF2F2F7)
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF075985),
    onPrimary = Color.White,
    secondary = Color(0xFF166534),
    onSecondary = Color.White,
    tertiary = Color(0xFF92400E),
    onTertiary = Color.White,
    background = Color(0xFFF8FAFC),
    surface = Color.White,
    onBackground = Slate900,
    onSurface = Slate900
)

@Composable
fun ContactLogoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
