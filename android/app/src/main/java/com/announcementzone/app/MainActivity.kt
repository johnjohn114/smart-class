package com.announcementzone.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

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

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* Permission result is handled by Android system settings. */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(35, 42, 105)
        window.navigationBarColor = android.graphics.Color.rgb(20, 24, 65)

        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
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
                    FeatureScreen(
                        title = "最新公告",
                        description = "公告列表、分類、重要公告與公告內容將在這裡提供。",
                        features = listOf("最新公告", "公告分類", "重要公告", "公告詳細內容")
                    )
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
                    FeatureScreen(
                        title = "會員中心",
                        description = "登入後管理個人資料、成長紀錄與服務。",
                        features = listOf(
                            "登入／登出與個人資料",
                            "競賽、簽到、徽章與活動紀錄",
                            "點數、等級、任務與成就",
                            "通知、優惠券與獎勵兌換",
                            "訂單、客服與回覆",
                            "設定、下載與版本更新"
                        )
                    )
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
