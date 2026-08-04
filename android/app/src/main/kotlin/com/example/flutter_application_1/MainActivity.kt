package com.example.flutter_application_1

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots, screen recording, and app-switcher previews of
        // financial customer data (BVN/NIN, loan details).
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
