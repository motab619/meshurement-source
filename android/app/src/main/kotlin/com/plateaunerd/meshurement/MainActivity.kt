// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

package com.plateaunerd.meshurement

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Channel `mesh_analyzer/app`, the Android side of AppDelegate's:
 *
 * - `launchArguments` → List<String>, what iOS returns from
 *   ProcessInfo.arguments, built from the launch Intent's extras. Each iOS
 *   launch flag `-Name` is the extra `Name` (no dash): a boolean extra
 *   (`--ez Name true`) is the bare flag, a string (`--es`) or int (`--ei`)
 *   extra is the flag followed by its value, and the string array `args`
 *   (`--esa args -a,-b`) is appended verbatim. So:
 *   `MeshDemo` → "-MeshDemo"; `demoScreen` → "-demoScreen", value;
 *   `demoSite` → "-demoSite", value; `MeshBench` → "-MeshBench";
 *   `benchPort` → "-benchPort", value (`BenchMode`, bench builds only).
 *   Demo mode from adb:
 *   `adb shell am start -n com.plateaunerd.meshurement/.MainActivity
 *    --ez MeshDemo true --es demoScreen report`
 *   Bench mode (tool/bench/bench/phones/android.py):
 *   `adb shell am start -S -n com.plateaunerd.meshurement/.MainActivity
 *    --ez MeshBench true --ei benchPort 8765`
 * - `openedFile` → String? content/file URI of the `.mabackup` the app was
 *   opened with (VIEW intent, at launch or later via onNewIntent), or null.
 *   Reading it clears it, so a file is handed over once. Android only; the
 *   Dart consumer is still to come.
 * - `moveToBack` → `moveTaskToBack(true)`: the app goes behind the home
 *   screen with its engine alive (Dart's answer to system back on the root
 *   tab; `AppChannel.moveToBack`).
 */
class MainActivity : FlutterActivity() {
    private var launchArgs: List<String> = emptyList()
    private var openedFile: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readIntent(intent, launch = true)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchArguments" -> result.success(launchArgs)
                    "openedFile" -> {
                        result.success(openedFile)
                        openedFile = null
                    }
                    // Back on the root tab: behind the home screen, not
                    // finished. Finishing destroys the Flutter engine and
                    // with it a recording session (first A16 walk, 2026-11-08).
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIntent(intent, launch = false)
    }

    private fun readIntent(intent: Intent?, launch: Boolean) {
        if (intent == null) return
        if (launch) {
            launchArgs = launchArgumentsOf(intent)
        }
        if (intent.action == Intent.ACTION_VIEW) {
            intent.data?.let { openedFile = it.toString() }
        }
    }

    companion object {
        private const val CHANNEL = "mesh_analyzer/app"

        /** Launch flags whose extra, when present, stands alone (`--ez`). */
        private val FLAGS = listOf("MeshDemo", "MeshBench")

        /** Launch flags that take a value (`--es`, or `--ei` for a number). */
        private val VALUED = listOf("demoScreen", "demoSite", "benchPort")

        /** The iOS-style argument list for an Intent's extras (see the class doc). */
        @Suppress("DEPRECATION") // Bundle.get: the extra's type is the caller's choice
        fun launchArgumentsOf(intent: Intent): List<String> {
            val args = mutableListOf<String>()
            val extras = intent.extras
            for (name in FLAGS) {
                // `--ez X false` is also a request not to turn it on.
                if (extras != null && extras.containsKey(name) &&
                    extras.getBoolean(name, true)) {
                    args.add("-$name")
                }
            }
            for (name in VALUED) {
                val raw = extras?.get(name) ?: continue
                args.add("-$name")
                args.add(raw.toString())
            }
            intent.getStringArrayExtra("args")?.let { args.addAll(it) }
            return args
        }
    }
}
