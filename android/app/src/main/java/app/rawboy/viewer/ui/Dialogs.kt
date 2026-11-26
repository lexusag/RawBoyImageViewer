package app.rawboy.viewer.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rawboy.viewer.data.StartupMode
import app.rawboy.viewer.data.ViewerPrefs
import app.rawboy.viewer.handoff.AutoImportMode
import app.rawboy.viewer.xmp.ConflictResolution
import app.rawboy.viewer.xmp.XmpConflict
import app.rawboy.viewer.xmp.XmpSyncResult

@Composable
fun XmpConflictDialog(
    conflicts: List<XmpConflict>,
    onResolve: (ConflictResolution) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
        title = { Text("XMP sidecars changed elsewhere", color = DarkroomColours.PaperWhite) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "${conflicts.size} photo(s) were rated in another app since this phone last wrote their XMP. " +
                        "By default, XMP ratings win and the phone updates to match.",
                    color = DarkroomColours.AshMuted,
                    fontSize = 13.sp,
                )
                conflicts.take(5).forEach { c ->
                    Text(
                        "• ${c.photo.relPath}: phone ${c.phoneRating.stars}★ vs XMP ${c.xmpRating.stars}★",
                        color = DarkroomColours.PaperWhite,
                        fontSize = 12.sp,
                    )
                }
                if (conflicts.size > 5) {
                    Text("…and ${conflicts.size - 5} more", color = DarkroomColours.AshMuted, fontSize = 12.sp)
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onResolve(ConflictResolution.KEEP_XMP) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = DarkroomColours.SafelightAmber,
                    contentColor = DarkroomColours.AmberInk,
                ),
            ) {
                Text("Keep XMP ratings")
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = { onResolve(ConflictResolution.KEEP_PHONE) }) {
                    Text("Keep phone", color = DarkroomColours.PaperWhite)
                }
                TextButton(onClick = { onResolve(ConflictResolution.SKIP) }) {
                    Text("Skip", color = DarkroomColours.AshMuted)
                }
            }
        },
    )
}

@Composable
fun XmpResultDialog(
    result: XmpSyncResult,
    onDismiss: () -> Unit,
) {
    val parts = buildList {
        add("Wrote ${result.written} sidecars")
        if (result.keptXmp > 0) add("${result.keptXmp} kept XMP")
        if (result.skipped > 0) add("${result.skipped} skipped")
        if (result.failed.isNotEmpty()) add("${result.failed.size} failed")
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
        title = { Text("XMP sync complete", color = DarkroomColours.PaperWhite) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(parts.joinToString(" · "), color = DarkroomColours.PaperWhite, fontSize = 14.sp)
                if (result.failed.isNotEmpty()) {
                    Text("Failed: ${result.failed.take(5).joinToString(", ")}", color = DarkroomColours.WarningRed, fontSize = 12.sp)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("OK", color = DarkroomColours.SafelightAmber) }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendToAutoSheet(
    photoCount: Int,
    rawBoyAutoInstalled: Boolean,
    initialMode: AutoImportMode,
    initialIncludeJpegs: Boolean,
    onSend: (AutoImportMode, Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    var mode by remember { mutableStateOf(initialMode) }
    var includeJpegs by remember { mutableStateOf(initialIncludeJpegs) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                if (rawBoyAutoInstalled) "Send $photoCount photo(s) to RawBoy Auto"
                else "Share $photoCount photo(s) (RawBoy Auto not installed)",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = DarkroomColours.PaperWhite,
            )
            if (rawBoyAutoInstalled) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (m in AutoImportMode.entries) {
                        FilterChip(
                            selected = mode == m,
                            onClick = { mode = m },
                            label = { Text(m.label) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = DarkroomColours.SafelightAmber,
                                selectedLabelColor = DarkroomColours.AmberInk,
                                containerColor = DarkroomColours.GraphiteRaised,
                                labelColor = DarkroomColours.PaperWhite,
                            ),
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Include paired JPEGs", color = DarkroomColours.PaperWhite, fontSize = 14.sp)
                    Text("Off sends raws only", color = DarkroomColours.AshMuted, fontSize = 12.sp)
                }
                Switch(
                    checked = includeJpegs,
                    onCheckedChange = { includeJpegs = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = DarkroomColours.AmberInk, checkedTrackColor = DarkroomColours.SafelightAmber),
                )
            }
            Button(
                onClick = { onSend(mode, includeJpegs) },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = DarkroomColours.SafelightAmber,
                    contentColor = DarkroomColours.AmberInk,
                ),
            ) {
                Text(if (rawBoyAutoInstalled) "Send to RawBoy Auto" else "Share")
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
fun SettingsDialog(
    prefs: ViewerPrefs,
    onStartupMode: (StartupMode) -> Unit,
    onPickDefaultFolder: () -> Unit,
    onGroupBySubfolders: (Boolean) -> Unit,
    onAutoAdvance: (Boolean) -> Unit,
    onWriteXmpBeforeSend: (Boolean) -> Unit,
    onIncludeJpegs: (Boolean) -> Unit,
    onEnableBin: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
        title = { Text("Settings", color = DarkroomColours.PaperWhite) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Open at launch", color = DarkroomColours.AshMuted, fontSize = 12.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (mode in StartupMode.entries) {
                        FilterChip(
                            selected = prefs.startupMode == mode,
                            onClick = { onStartupMode(mode) },
                            label = { Text(mode.label, fontSize = 11.sp) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = DarkroomColours.SafelightAmber,
                                selectedLabelColor = DarkroomColours.AmberInk,
                                containerColor = DarkroomColours.GraphiteRaised,
                                labelColor = DarkroomColours.PaperWhite,
                            ),
                        )
                    }
                }
                if (prefs.startupMode == StartupMode.CUSTOM) {
                    TextButton(onClick = onPickDefaultFolder) {
                        val label = prefs.defaultFolderUri?.substringAfterLast("%2F")?.substringAfterLast("%3A")
                        Text(
                            if (label != null) "Default folder: $label (change)" else "Choose default folder…",
                            color = DarkroomColours.SafelightAmber,
                            fontSize = 12.sp,
                        )
                    }
                }
                SettingToggle("Group by subfolders", prefs.groupBySubfolders, onGroupBySubfolders)
                SettingToggle("Auto-advance after rating", prefs.autoAdvanceAfterRating, onAutoAdvance)
                SettingToggle("Write XMP before sending to RawBoy", prefs.writeXmpBeforeSend, onWriteXmpBeforeSend)
                SettingToggle("Include paired JPEGs in batches", prefs.includeJpegsInBatch, onIncludeJpegs)
                SettingToggle("Enable _bin option for rejects", prefs.enableBinOption, onEnableBin)
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done", color = DarkroomColours.SafelightAmber) }
        },
    )
}

@Composable
fun DeleteConfirmDialog(
    count: Int,
    singleFileName: String?,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
        title = {
            Text(
                if (count == 1) "Delete photo?" else "Delete $count photos?",
                color = DarkroomColours.PaperWhite,
            )
        },
        text = {
            val detail = if (count == 1 && singleFileName != null) {
                "\"$singleFileName\" (plus any paired JPEG and XMP sidecars) will be permanently deleted."
            } else {
                "$count selected items (plus any paired JPEGs and XMP sidecars) will be permanently deleted."
            }
            Text(detail, color = DarkroomColours.AshMuted, fontSize = 13.sp)
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = DarkroomColours.WarningRed,
                    contentColor = DarkroomColours.InkBlack,
                ),
            ) {
                Text("Delete")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = DarkroomColours.PaperWhite)
            }
        },
    )
}

@Composable
fun HelpDialog(
    versionName: String,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = DarkroomColours.GraphiteSurface,
        title = {
            Column {
                Text("RawBoy Viewer", color = DarkroomColours.PaperWhite, fontWeight = FontWeight.SemiBold)
                Text("Android · v$versionName", color = DarkroomColours.AshMuted, fontSize = 12.sp)
            }
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                HelpSection(
                    title = "Browser",
                    items = listOf(
                        "Open folder" to "Tap the folder icon to pick any folder (internal storage, SD card, USB reader). Opens Pictures & DCIM by default; change in Settings.",
                        "Subfolders" to "Tap a subfolder header to fold or unfold it. Long-press a header to select or deselect the whole subfolder. The current folder stays pinned while scrolling.",
                        "Multi-select" to "Long-press a photo, then tap others to add or remove. Press Back to clear.",
                        "Filter & sort" to "Filter by All, Picks, Unflagged, Rejects and minimum stars. Tap the sort icon for capture date or name.",
                    ),
                )
                HorizontalDivider(color = DarkroomColours.Hairline)
                HelpSection(
                    title = "Viewer & Video",
                    items = listOf(
                        "Next / previous" to "Swipe left or right (follows subfolder grouping when enabled).",
                        "Zoom" to "Double-tap to zoom into that point and render full resolution; double-tap again to fit. Pinch to zoom around your fingers and drag to pan.",
                        "Exit" to "Press Back or tap ← to return to your exact position in the grid. Single tap hides or shows the bars.",
                        "Details" to "Tap i for EXIF and RGB histogram (pinned on the right on tablets).",
                        "Videos" to "Play/pause, mute, and drag the timeline to scrub.",
                    ),
                )
                HorizontalDivider(color = DarkroomColours.Hairline)
                HelpSection(
                    title = "Culling, XMP & Delete",
                    items = listOf(
                        "Rate & flag" to "Use 1–5 stars, Pick (flag), and Reject (×). Tapping the same star or flag clears it. Undo reverses the last change.",
                        "Local database" to "Ratings stay in a local database so photo folders aren't modified while culling. An amber dot marks ratings not yet written to XMP.",
                        "Write XMP" to "Tap Write XMP (in the filter bar or menu) to write xmp:Rating and rawboy:Pick in place, keeping all other metadata intact. On conflicts, existing XMP wins by default (you can override).",
                        "Delete / _bin" to "Tap the red trash icon to delete immediately (with paired JPEG and sidecars), or move rejects into _bin from the menu.",
                    ),
                )
                HorizontalDivider(color = DarkroomColours.Hairline)
                HelpSection(
                    title = "Send to RawBoy",
                    items = listOf(
                        "RawBoy Pro" to "Tap RawBoy in the viewer or single-photo selection to open in RawBoy.",
                        "RawBoy Auto" to "Tap the amber send icon to send a photo, selection, or visible filter (e.g. Picks) as a batch (Looks / Film / As is). Sends raws by default; toggle Include paired JPEGs if needed.",
                    ),
                )
                HorizontalDivider(color = DarkroomColours.Hairline)
                HelpSection(
                    title = "Tablet keyboard shortcuts",
                    items = listOf(
                        "← / → / Space" to "Previous / next photo",
                        "1–5 / 0" to "Set or clear stars",
                        "P / X / U" to "Pick / Reject / Unflag",
                        "I" to "Toggle details",
                        "Ctrl/⌘Z · Esc" to "Undo · back to grid",
                    ),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close", color = DarkroomColours.SafelightAmber) }
        },
    )
}

@Composable
private fun HelpSection(title: String, items: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = DarkroomColours.SafelightAmber, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        for ((k, v) in items) {
            Column {
                Text(k, color = DarkroomColours.PaperWhite, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                Text(v, color = DarkroomColours.AshMuted, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
    }
}

@Composable
private fun SettingToggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = DarkroomColours.PaperWhite, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = DarkroomColours.AmberInk,
                checkedTrackColor = DarkroomColours.SafelightAmber,
            ),
        )
    }
}
