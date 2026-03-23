# Интеграция llama.cpp для парсинга сценариев

## 📋 Обзор

llama.cpp - это C++ библиотека для работы с LLM моделями на iOS. Она поддерживает TinyLlama и другие модели в формате GGUF.

## 🚀 Шаги интеграции

### Шаг 1: Добавить llama.cpp в проект

#### Вариант A: Через Swift Package Manager (рекомендуется)

1. Откройте Xcode проект
2. File → Add Package Dependencies...
3. Введите URL: `https://github.com/ggerganov/llama.cpp`
4. Выберите версию (последняя стабильная)
5. Добавьте в Target: `shafinMultitool`

#### Вариант B: Вручную (если SPM не работает)

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   ```

2. Соберите для iOS:
   ```bash
   # Создайте Xcode проект
   cmake -B build -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
   ```

3. Добавьте собранную библиотеку в Xcode проект

### Шаг 2: Скачать модель TinyLlama в формате GGUF

1. Перейдите на HuggingFace: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
2. Скачайте квантизованную версию: `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` (~700MB)
   - Q4_K_M - хороший баланс между размером и качеством
   - Можно использовать Q8_0 для лучшего качества (больше размер)

3. Добавьте модель в Xcode проект:
   - Перетащите `.gguf` файл в папку `SceneGeneratorModule/Models/`
   - Убедитесь что "Copy items if needed" отмечено
   - Проверьте Target Membership

### Шаг 3: Создать Swift обёртку для llama.cpp

Создайте файл `SceneGeneratorModule/Services/LlamaCppWrapper.swift`:

```swift
import Foundation

// Обёртка для C функций llama.cpp
@_cdecl("llama_backend_init")
func llama_backend_init() {
    // Вызов C функции
}

// Добавьте другие необходимые функции
// См. документацию llama.cpp для полного списка API
```

### Шаг 4: Обновить LLMParserService

Раскомментируйте и доработайте код в `LLMParserService.swift`:

1. В методе `loadModel()` - загрузка модели через llama.cpp
2. В методе `generateText()` - генерация текста

### Шаг 5: Тестирование

1. Запустите приложение
2. Введите сложный сценарий
3. Проверьте что LLM fallback срабатывает при низкой confidence

## 📝 Примеры использования

### Загрузка модели

```swift
let modelPath = Bundle.main.path(forResource: "tinyllama-1.1b-chat-v1.0", ofType: "gguf")
// Инициализация через llama.cpp API
```

### Генерация текста

```swift
let prompt = "Парси сцену: 2 актёра идут навстречу"
let response = generateText(prompt: prompt)
// Ожидаемый ответ: JSON с распарсенным сценарием
```

## ⚠️ Важные замечания

1. **Размер модели**: GGUF модель занимает ~700MB-1GB
   - Убедитесь что есть место в проекте
   - Рассмотрите возможность загрузки модели по требованию

2. **Производительность**: 
   - Первый запуск может быть медленным (загрузка модели)
   - Генерация токенов занимает время (зависит от устройства)

3. **Память**:
   - Модель загружается в RAM
   - Убедитесь что устройство имеет достаточно памяти

## 🔗 Полезные ссылки

- llama.cpp репозиторий: https://github.com/ggerganov/llama.cpp
- Документация API: https://github.com/ggerganov/llama.cpp/blob/master/llama.h
- TinyLlama GGUF модели: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
- Примеры интеграции: https://github.com/ggerganov/llama.cpp/tree/master/examples

## 🎯 Альтернатива: Готовые Swift обёртки

Если интеграция llama.cpp вручную сложна, рассмотрите готовые Swift обёртки:

- **llama.swift**: https://github.com/ggerganov/llama.swift (если есть)
- Или используйте серверный API для сложных случаев
