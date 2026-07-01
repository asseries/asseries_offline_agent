# Aida — Offline AI Agent (Flutter Edition)

Gemma-chat Electron/React loyihasining Flutter'dagi to'liq implementatsiyasi.  
Model: `qwen2.5-coder:latest` | Backend: Ollama | Platform: macOS/Windows/Linux

---

## Loyiha tuzilmasi

```
asseries_offline_agent/
├── lib/
│   ├── main.dart                        # App entry point + ProviderScope
│   ├── models/
│   │   ├── conversation.dart            # Conversation data class (id, title, messages, mode)
│   │   ├── message.dart                 # Message (user/assistant/tool), AgentActivity
│   │   └── tool_call.dart               # ToolCall, ParsedAction data classes
│   ├── services/
│   │   ├── ollama_service.dart          # Ollama HTTP streaming client
│   │   ├── agent_loop.dart              # Agent loop — asosiy AI mantiq
│   │   ├── tools.dart                   # XML parser + barcha tool'lar
│   │   └── workspace_service.dart       # Fayl tizimi (har conversation uchun alohida)
│   ├── storage/
│   │   └── storage_service.dart         # SharedPreferences orqali conversation saqlash
│   ├── providers/
│   │   └── chat_provider.dart           # Riverpod state (ChatNotifier, SettingsNotifier)
│   └── ui/
│       ├── app_theme.dart               # Qorong'u mavzu, AppColors
│       ├── screens/
│       │   └── home_screen.dart         # Asosiy layout: sidebar + chat + canvas
│       └── widgets/
│           ├── sidebar.dart             # Conversation ro'yxati
│           ├── chat_view.dart           # Xabarlar ro'yxati
│           ├── message_bubble.dart      # Har bir xabar (user/assistant/thinking/tool)
│           ├── composer.dart            # Matn kiritish maydoni
│           ├── canvas_panel.dart        # Fayl daraxti + kod ko'ruvchi
│           └── tool_card.dart           # Tool chaqiruv kartasi
├── macos/Runner/
│   ├── DebugProfile.entitlements        # Sandbox o'chirilgan (debug uchun)
│   └── Release.entitlements             # Sandbox o'chirilgan
└── pubspec.yaml                         # Dependency'lar
```

---

## Ishlash printsipi (Algoritm)

### 1. Agent Loop — `lib/services/agent_loop.dart`

Gemma-chat'ning `handleChat()` funksiyasiga mos keladigan asosiy tsikl:

```
foydalanuvchi xabari
        │
        ▼
┌─────────────────────────────────────────────┐
│  Agent Loop (max 40 tur — code, 6 — chat)   │
│                                             │
│  1. System prompt yaratish (mode'ga qarab)  │
│  2. Ollama /api/chat ga POST (stream: true) │
│  3. Token'lar oqimini o'qish (NDJSON)       │
│  4. <think> bloklarini ajratish             │
│  5. Xavfsiz chegarani topish (emit)         │
│  6. <action> bloki to'liq bo'ldimi?         │
│     ├── YO'Q: keyingi token'ni kuting       │
│     └── HA:  ──────────────────────────┐   │
│                                        │   │
│  Tool bajarish:                        │   │
│  write_file / read_file / run_bash...  │   │
│                                        │   │
│  Natijani messages'ga qo'shish         │   │
│  Keyingi turga o'tish ◄────────────────┘   │
└─────────────────────────────────────────────┘
        │
        ▼
   Action topilmadi → DoneEvent → UI yangilanadi
```

### 2. XML Tool Parseri — `lib/services/tools.dart`

Gemma-chat'ning `findNextAction()` algoritmi bilan bir xil:

```
Kiruvchi matn: "...bu faylni yozaman: <action name="write_file"><path>app.js</path><content>...</content></action>..."

1. `<action name="...">` topish
2. `</action>` oxiri topish  
3. name attribute'ni ajratish
4. `<param>value</param>` juftliklarini parse qilish
5. `<content>` uchun OXIRGI `</content>` ishlatish (ichida HTML bo'lsa ham ishlaydi)
6. ParsedAction {name, args, startIndex, endIndex} qaytarish
```

**Xavfsiz chegara (`findSafeBoundary`):**  
Token'lar oqimida `<action` boshlanayotgan bo'lsa, to'liq tag kelgunicha UI'ga ko'rsatmaydi. Bu gemma-chat'ning `emitSafeBoundary()` funksiyasiga mos.

### 3. Token Streaming — `lib/services/ollama_service.dart`

```
POST http://localhost:11434/api/chat
{
  "model": "qwen2.5-coder:latest",
  "messages": [...],
  "stream": true
}

Javob: NDJSON oqimi
{"message": {"role": "assistant", "content": "salom"}, "done": false}
{"message": {"role": "assistant", "content": " dost"}, "done": false}
{"done": true}
```

Dart'da `http.Request.send()` → `response.stream` → `utf8.decoder` → `LineSplitter()` orqali har bir JSON satr real vaqtda qayta ishlanadi.

### 4. State Management — Riverpod

```dart
// Ikkita asosiy provider:

// 1. Sozlamalar (model, Ollama holati)
settingsProvider: StateNotifierProvider<SettingsNotifier, AppSettings>

// 2. Chat holati (conversations, streaming, activeId)  
chatProvider: StateNotifierProvider<ChatNotifier, ChatState>
```

**Data oqimi:**
```
Foydalanuvchi yozadi
    │
    ▼
Composer → chatProvider.notifier.sendMessage()
    │
    ▼
runAgentLoop() — async Stream<AgentEvent>
    │
    ├── TokenEvent    → assistantMsg.content yangilaydi → _notify() → UI
    ├── ActivityEvent → spinner ko'rsatadi
    ├── ToolStartEvent→ ToolCard qo'shadi
    ├── ToolDoneEvent → ToolCard natijasini yangilaydi
    └── DoneEvent     → streaming = false, saqlaydi
```

### 5. Workspace — `lib/services/workspace_service.dart`

Har bir conversation o'z papkasiga ega:
```
~/Library/Application Support/asseries_offline_agent/workspaces/
└── {conversationId}/
    ├── index.html
    ├── style.css
    └── app.js
```

Gemma-chat kabi:
- **Atomik yozish**: avval `.tmp` faylga, keyin rename
- **Path validation**: `../` orqali qochishning oldini olish
- **Bash deny list**: `rm -rf /`, `sudo`, `shutdown` va boshqalar bloklangan
- **Bash output limit**: 16KB max, 60 soniya timeout

---

## UI Tuzilmasi

### Layout (gemma-chat bilan bir xil)

```
┌─────────────────────────────────────────────────────────┐
│                         macOS oyna                      │
├──────────┬──────────────────────────────┬───────────────┤
│          │  Header (mode toggle, model) │               │
│          ├──────────────────────────────┤               │
│ Sidebar  │                              │    Canvas     │
│          │     Chat View                │    (ixtiyoriy)│
│ - New    │     (xabarlar ro'yxati)      │               │
│ - Code   │                              │  ┌──────────┐ │
│   conv.  │                              │  │ Files    │ │
│          │                              │  │ Code     │ │
│ [conv1]  ├──────────────────────────────┤  └──────────┘ │
│ [conv2]  │      Composer                │               │
│ [conv3]  │   (matn + model + send)      │               │
└──────────┴──────────────────────────────┴───────────────┘
```

### Mavzu (AppColors)

| Rang | Hex | Ishlatilishi |
|------|-----|--------------|
| `bg` | `#0f0f11` | Asosiy fon |
| `surface` | `#18181b` | Panel'lar foni |
| `surfaceHigh` | `#27272a` | Hover, tanlangan |
| `border` | `#3f3f46` | Chegaralar |
| `textDim` | `#71717a` | Ikkinchi darajali matn |
| `text` | `#e4e4e7` | Oddiy matn |
| `textBright` | `#fafafa` | Asosiy matn |
| `accent` | `#6366f1` | Indigo, asosiy rang |
| `green` | `#22c55e` | Muvaffaqiyat, run_bash |
| `red` | `#ef4444` | Xato, stop tugmasi |

---

## Tool'lar

| Tool | Gemma-chat'da | Flutter'da |
|------|---------------|------------|
| `write_file` | ✅ | ✅ |
| `read_file` | ✅ | ✅ |
| `edit_file` | ✅ | ✅ (find & replace) |
| `delete_file` | ✅ | ✅ |
| `list_files` | ✅ | ✅ |
| `run_bash` | ✅ | ✅ (dart:io Process) |
| `calc` | ✅ | ✅ (recursive descent parser) |
| `web_search` | ✅ | ❌ (hozircha yo'q) |
| `fetch_url` | ✅ | ❌ (hozircha yo'q) |
| Live preview | ✅ iframe | ❌ (webview_flutter qo'shsa bo'ladi) |
| Speech-to-text | ✅ Whisper | ❌ (hozircha yo'q) |

---

## Ishlatish

### Talablar
- [Ollama](https://ollama.ai) o'rnatilgan va ishlamoqda
- `qwen2.5-coder:latest` modeli yuklab olingan:
  ```bash
  ollama pull qwen2.5-coder:latest
  ```

### Ishga tushirish

**Debug rejimida:**
```bash
cd ~/Desktop/asseries_offline_agent
flutter run -d macos
```

**Release build:**
```bash
flutter build macos --release
# .app fayl: build/macos/Build/Products/Release/asseries_offline_agent.app
```

### Agent modlari

| Mod | Tasvirlanish | Max tur |
|-----|-------------|---------|
| **Chat** | Oddiy suhbat, `calc` tool | 6 |
| **Code** | To'liq fayl operatsiyalari, bash, barcha tool'lar | 40 |

---

## Gemma-chat vs Aida Flutter: Farqlar

| Jihat | Gemma-chat (Original) | Aida Flutter |
|-------|----------------------|--------------|
| Framework | Electron + React | Flutter |
| Til | TypeScript | Dart |
| LLM backend | MLX-LM (Apple Silicon) | Ollama (cross-platform) |
| State | React hooks + localStorage | Riverpod + SharedPreferences |
| Markdown | marked.js | flutter_markdown |
| Syntax highlight | highlight.js | flutter_highlight |
| Preview | iframe (Node.js server) | webview_flutter (qo'shsa bo'ladi) |
| STT | Whisper.js (WebGPU) | — |
| Platform | macOS only | macOS, Windows, Linux, mobile |
| Agent loop | `handleChat()` async/await | `runAgentLoop()` Dart Stream |

---

## Dependency'lar

```yaml
flutter_riverpod: ^2.5.1     # State management
http: ^1.2.1                  # Ollama API
shared_preferences: ^2.3.2   # Conversation saqlash
path_provider: ^2.1.4        # Fayl yo'llari
flutter_markdown: ^0.7.4     # Markdown render
flutter_highlight: ^0.7.0    # Syntax highlighting
highlight: ^0.7.0             # Highlight engine
uuid: ^4.5.1                  # Unique ID generatsiya
path: ^1.9.0                  # Fayl yo'l operatsiyalari
```
