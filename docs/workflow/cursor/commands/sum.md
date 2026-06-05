# sum
# DIPLOMA LOGGING RULE
When I use the command "/sum" or ask to "записать прогресс в диплом", you must perform the following actions:

1.  **Read Context:** Analyze the conversation history of the current session and the code changes made (or use git commands).
2.  **Read File:** Read the current content of `diploma.md` to avoid duplicates.
3.  **Append:** Add a new entry to `diploma.md` at the end of the file.
4.  **Format:** Use the following format for the new entry:

## [YYYY-MM-DD HH:MM] - [Краткое название задачи/фичи]

### Суть изменений
- Кратко: что было сделано (bullet points).

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** С какой технической трудностью столкнулись (например: "высокая нагрузка на GPU", "рассинхрон потоков", "нехватка памяти").
- **Решение:** Как именно это решили технически (например: "использована квантизация", "применен паттерн Observer", "написан кастомный шейдер").
- **Детали:** Если были использованы формулы, специфические настройки гиперпараметров или нетривиальная логика — опиши их здесь. Это пригодится для главы "Реализация".

### Ключевые файлы
- `filename.ext` (функция X)

---

**Tone:** Academic, technical, precise. Focus on "WHY" and "HOW", not just "WHAT".
