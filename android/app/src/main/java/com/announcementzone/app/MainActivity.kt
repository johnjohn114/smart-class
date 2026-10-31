package com.announcementzone.app

import android.app.Activity
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import android.view.View
import android.webkit.DownloadListener
import android.webkit.JavascriptInterface

class MainActivity : Activity() {
    private lateinit var webView: WebView
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private val homeUrl = "https://johnjohn114.github.io/smart-class/"
    private val fileRequest = 1001
    private inner class AppInfoBridge {
        @JavascriptInterface fun getVersionCode(): Int = BuildConfig.VERSION_CODE
        @JavascriptInterface fun getVersionName(): String = BuildConfig.VERSION_NAME
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(35, 42, 105)
        window.navigationBarColor = android.graphics.Color.rgb(20, 24, 65)
        webView = WebView(this)
        setContentView(webView)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadsImagesAutomatically = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(false)
            allowFileAccess = false
        }
        CookieManager.getInstance().apply { setAcceptCookie(true); setAcceptThirdPartyCookies(webView, true) }
        webView.addJavascriptInterface(AppInfoBridge(), "AndroidApp")
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                val script = """
                    (function(){
                      if(window.__appReleaseCheckInstalled)return;
                      window.__appReleaseCheckInstalled=true;
                      if(!window.AndroidApp || typeof SUPABASE_URL==='undefined' || typeof SUPABASE_ANON_KEY==='undefined')return;
                      var current=Number(AndroidApp.getVersionCode());
                      fetch(SUPABASE_URL+'/rest/v1/app_releases?select=version_code,version_name,release_notes,apk_url&published=eq.true&order=version_code.desc&limit=1',
                        {headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY}})
                      .then(function(r){return r.ok?r.json():[]}).then(function(rows){
                        var x=rows&&rows[0];
                        if(!x || Number(x.version_code)<=current || document.getElementById('appUpdateNotice'))return;
                        var box=document.createElement('div');box.id='appUpdateNotice';
                        box.style.cssText='position:fixed;z-index:2147483647;left:12px;right:12px;bottom:14px;padding:16px;border-radius:18px;background:#252d75;color:white;box-shadow:0 8px 30px #0005;font:14px sans-serif;';
                        var title=document.createElement('b');title.textContent='📱 事項公告區有新版 '+x.version_name;
                        var note=document.createElement('p');note.textContent=x.release_notes||'新版已推出，建議更新。';note.style.cssText='margin:8px 0;white-space:pre-wrap';
                        var link=document.createElement('a');link.href=x.apk_url;link.textContent='前往下載新版 APK';link.style.cssText='display:inline-block;background:white;color:#252d75;padding:9px 14px;border-radius:10px;text-decoration:none;font-weight:bold';
                        var close=document.createElement('button');close.textContent='稍後';close.style.cssText='float:right;background:transparent;color:white;border:1px solid #ffffff88;border-radius:10px;padding:8px 12px';close.onclick=function(){box.remove()};
                        box.append(title,close,note,link);document.body.appendChild(box);
                      }).catch(function(){});
                    })();
                """.trimIndent()
                view.evaluateJavascript(script, null)
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                return if (uri.scheme == "https" && (uri.host == "johnjohn114.github.io" || uri.host?.endsWith("supabase.co") == true)) false
                else if (uri.scheme == "http" || uri.scheme == "https") { startActivity(Intent(Intent.ACTION_VIEW, uri)); true }
                else true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = callback
                return try { startActivityForResult(params.createIntent(), fileRequest); true }
                catch (_: Exception) { fileCallback = null; false }
            }
        }
        webView.setDownloadListener(DownloadListener { url, _, contentDisposition, mimeType, _ ->
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(intent)
            } catch (_: Exception) { Toast.makeText(this, "無法開啟下載連結", Toast.LENGTH_SHORT).show() }
        })
        if (savedInstanceState == null) webView.loadUrl(homeUrl) else webView.restoreState(savedInstanceState)
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == fileRequest) {
            fileCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            fileCallback = null
        }
    }
    override fun onSaveInstanceState(outState: Bundle) { super.onSaveInstanceState(outState); webView.saveState(outState) }
    @Deprecated("Deprecated in Android API")
    override fun onBackPressed() { if (webView.canGoBack()) webView.goBack() else super.onBackPressed() }
    override fun onDestroy() { fileCallback?.onReceiveValue(null); webView.destroy(); super.onDestroy() }
}
