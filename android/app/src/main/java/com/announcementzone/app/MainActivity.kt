package com.announcementzone.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.launch

private data class AppTab(val route: String, val title: String, val symbol: String)

private val appTabs = listOf(
    AppTab("home", "首頁", "⌂"),
    AppTab("announcements", "公告", "▤"),
    AppTab("activities", "活動", "★"),
    AppTab("calendar", "行事曆", "▦"),
    AppTab("member", "會員", "●")
)

private val BrandBlue = Color(0xFF252D75)
private val PageBackground = Color(0xFFF4F6FC)

class MainActivity : ComponentActivity() {
    private var appNavController: NavHostController? = null

    private val notificationPermissionRequestCode = 2001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(35, 42, 105)
        window.navigationBarColor = android.graphics.Color.rgb(20, 24, 65)

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode
            )
        }

        setContent {
            SmartClassApp(
                openAnnouncements = intent.getStringExtra("announcement_url") != null,
                onNavReady = { appNavController = it }
            )
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getStringExtra("announcement_url") != null) {
            appNavController?.navigate("announcements") {
                launchSingleTop = true
            }
        }
    }
}

@Composable
private fun SmartClassApp(
    openAnnouncements: Boolean,
    onNavReady: (NavHostController) -> Unit
) {
    val navController = rememberNavController()
    val context = LocalContext.current
    val authRepository = remember { SupabaseAuthRepository(context) }
    SideEffect { onNavReady(navController) }

    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = BrandBlue,
            secondary = Color(0xFF6875C5),
            background = PageBackground,
            surface = Color.White
        )
    ) {
        Scaffold(
            containerColor = PageBackground,
            bottomBar = {
                val backStack = navController.currentBackStackEntryAsState()
                val currentRoute = backStack.value?.destination?.route
                NavigationBar(containerColor = Color.White) {
                    appTabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Text(tab.symbol, fontSize = 19.sp) },
                            label = { Text(tab.title) }
                        )
                    }
                }
            }
        ) { padding ->
            NavHost(
                navController = navController,
                startDestination = if (openAnnouncements) "announcements" else "home",
                modifier = Modifier.padding(padding)
            ) {
                composable("home") { HomeScreen(onOpen = { navController.navigate(it) }) }
                composable("announcements") {
                    AnnouncementsScreen(repository = authRepository)
                }
                composable("activities") {
                    FeatureScreen(
                        title = "活動與競賽",
                        description = "查看活動、競賽資訊與排行榜。",
                        features = listOf("活動列表與分類", "即將開始／進行中／已結束", "競賽紀錄與成績", "活動排行榜")
                    )
                }
                composable("calendar") {
                    FeatureScreen(
                        title = "活動行事曆",
                        description = "以月曆方式查看公告與活動日期。",
                        features = listOf("月曆檢視", "上個月／下個月", "今日活動", "每日活動清單")
                    )
                }
                composable("member") {
                    MemberScreen(repository = authRepository)
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(onOpen: (String) -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BrandBlue, RoundedCornerShape(24.dp))
                    .padding(22.dp)
            ) {
                Text("SMART CLASS", color = Color(0xFFDDE2FF), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("事項公告區", color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                Text("公告、活動與學習紀錄，一站掌握", color = Color.White, fontSize = 14.sp)
            }
        }
        item {
            Text("快速前往", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
        }
        items(appTabs.filter { it.route != "home" }) { tab ->
            FeatureCard(
                title = tab.title,
                detail = when (tab.route) {
                    "announcements" -> "最新消息與重要公告"
                    "activities" -> "活動、競賽與排行榜"
                    "calendar" -> "月曆與每日活動"
                    else -> "個人資料、點數與會員服務"
                },
                symbol = tab.symbol,
                onClick = { onOpen(tab.route) }
            )
        }
        item {
            Text(
                "原生 App 正在建置中；既有網站與資料服務會持續保留。",
                color = Color(0xFF68708A),
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
private fun FeatureScreen(title: String, description: String, features: List<String>) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(title, fontSize = 25.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
            Spacer(Modifier.height(4.dp))
            Text(description, color = Color(0xFF68708A), fontSize = 14.sp)
        }
        items(features) { feature ->
            FeatureCard(title = feature, detail = "功能介面與 Supabase 資料串接將於後續階段完成。")
        }
    }
}

@Composable
private fun FeatureCard(
    title: String,
    detail: String,
    symbol: String = "•",
    onClick: (() -> Unit)? = null
) {
    Card(
        onClick = { onClick?.invoke() },
        enabled = onClick != null,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 17.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Surface(
                color = Color(0xFFEEF0FF),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(
                    symbol,
                    color = BrandBlue,
                    fontSize = 20.sp,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp)
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.SemiBold, color = Color(0xFF20264F), fontSize = 16.sp)
                Spacer(Modifier.height(3.dp))
                Text(detail, color = Color(0xFF68708A), fontSize = 12.sp)
            }
            if (onClick != null) Text("›", color = BrandBlue, fontSize = 24.sp)
        }
    }
}



@Composable
private fun AnnouncementsScreen(repository: SupabaseAuthRepository) {
    val context = LocalContext.current
    var announcements by remember { mutableStateOf<List<Announcement>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf("") }
    var reloadKey by remember { mutableStateOf(0) }

    LaunchedEffect(repository, reloadKey) {
        loading = true
        errorMessage = ""
        try {
            announcements = repository.loadAnnouncements()
        } catch (error: Exception) {
            errorMessage = error.message ?: "公告載入失敗，請稍後再試。"
        } finally {
            loading = false
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("最新公告", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
            Text("公告資訊即時讀取自網站公告資料。", color = Color(0xFF68708A), fontSize = 14.sp)
        }
        if (loading) {
            item {
                Row(Modifier.fillMaxWidth().padding(vertical = 28.dp), horizontalArrangement = Arrangement.Center) {
                    CircularProgressIndicator()
                }
            }
        } else if (errorMessage.isNotBlank()) {
            item {
                Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("公告載入失敗", fontWeight = FontWeight.Bold, color = Color(0xFFB3261E))
                        Text(errorMessage, color = Color(0xFF68708A), fontSize = 13.sp)
                        Button(onClick = { reloadKey++ }) { Text("重新載入") }
                    }
                }
            }
        } else if (announcements.isEmpty()) {
            item {
                Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Text("目前沒有已發布的公告。", modifier = Modifier.padding(18.dp), color = Color(0xFF68708A))
                }
            }
        } else {
            items(announcements, key = { it.id }) { announcement ->
                var expanded by remember(announcement.id) { mutableStateOf(false) }
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            (if (announcement.pinned) "📌 置頂 · " else "") +
                                announcement.date + " · " + announcement.category,
                            color = Color(0xFF68708A),
                            fontSize = 12.sp
                        )
                        Text(
                            announcement.title,
                            modifier = Modifier.fillMaxWidth(),
                            color = BrandBlue,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            softWrap = true
                        )
                        Text(
                            announcement.content.ifBlank { "（沒有公告內文）" },
                            modifier = Modifier.fillMaxWidth(),
                            color = Color(0xFF30354F),
                            fontSize = 14.sp,
                            softWrap = true,
                            maxLines = if (expanded) Int.MAX_VALUE else 5
                        )
                        if (announcement.content.length > 220 || announcement.content.count { it == '\\n' } >= 4) {
                            TextButton(onClick = { expanded = !expanded }) {
                                Text(if (expanded) "收起內容" else "閱讀完整公告")
                            }
                        }
                        if (!announcement.linkUrl.isNullOrBlank()) {
                            TextButton(onClick = {
                                runCatching {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(announcement.linkUrl)))
                                }
                            }) {
                                Text(announcement.linkLabel ?: "查看相關連結")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MemberScreen(repository: SupabaseAuthRepository) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var member by remember { mutableStateOf<MemberSession?>(null) }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    LaunchedEffect(repository) {
        loading = true
        member = repository.restoreSession()
        loading = false
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text("會員中心", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
            Text(
                "使用原本網站的 Supabase 會員帳號登入",
                color = Color(0xFF68708A),
                fontSize = 14.sp
            )
        }
        if (loading) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 36.dp),
                    horizontalArrangement = Arrangement.Center
                ) { CircularProgressIndicator() }
            }
        } else if (member == null) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White)
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text("會員登入", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
                        OutlinedTextField(
                            value = email,
                            onValueChange = { email = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Email") },
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = password,
                            onValueChange = { password = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("密碼") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation()
                        )
                        if (errorMessage.isNotBlank()) {
                            Text(errorMessage, color = Color(0xFFB3261E), fontSize = 13.sp)
                        }
                        Button(
                            onClick = {
                                if (email.isBlank() || password.isEmpty()) {
                                    errorMessage = "請輸入 Email 和密碼。"
                                } else {
                                    working = true
                                    errorMessage = ""
                                    scope.launch {
                                        try {
                                            member = repository.signIn(email, password)
                                            password = ""
                                        } catch (error: Exception) {
                                            errorMessage = error.message ?: "登入失敗，請稍後再試。"
                                        } finally {
                                            working = false
                                        }
                                    }
                                }
                            },
                            enabled = !working,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            if (working) {
                                CircularProgressIndicator(
                                    modifier = Modifier.height(18.dp),
                                    strokeWidth = 2.dp,
                                    color = Color.White
                                )
                            } else {
                                Text("登入")
                            }
                        }
                        Text(
                            "這裡不會要求你建立新帳號；請使用原本網站的會員帳號。",
                            color = Color(0xFF68708A),
                            fontSize = 12.sp
                        )
                    }
                }
            }
        } else {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White)
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(9.dp)
                    ) {
                        Text("登入成功", color = Color(0xFF247044), fontWeight = FontWeight.SemiBold)
                        Text(
                            member?.nickname?.takeIf { it.isNotBlank() } ?: "會員",
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = BrandBlue
                        )
                        MemberInfoRow("會員編號", member?.memberNumber ?: "—")
                        MemberInfoRow("Email", member?.email ?: "—")
                        MemberInfoRow("帳號身分", member?.role ?: "一般會員")
                        TextButton(
                            onClick = {
                                working = true
                                scope.launch {
                                    repository.signOut()
                                    member = null
                                    working = false
                                }
                            },
                            enabled = !working
                        ) { Text("登出") }
                    }
                }
            }
            item {
                Text("會員功能", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = BrandBlue)
                Text(
                    "個人資料、競賽紀錄、簽到、徽章、成長點數、通知、優惠券、獎勵、訂單與客服等功能將陸續接入。",
                    color = Color(0xFF68708A),
                    fontSize = 13.sp
                )
            }
        }
    }
}

@Composable
private fun MemberInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = Color(0xFF68708A), fontSize = 13.sp)
        Text(value, color = Color(0xFF20264F), fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}
