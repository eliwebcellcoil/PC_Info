# Disk Report System

כלי לאיסוף מצב דיסקים ומערכת במחשבי Windows, שמירת היסטוריה מרכזית, וניתוח תוצאות בדשבורד HTML.

**גרסאות נוכחיות**
- איסוף נתונים: `DiskReport.ps1` **v1.6.3**
- ניתוח / דשבורד: `DiskReport_Viewer.ps1` **v1.5.0**

---

## תוכן עניינים

1. [מה המערכת עושה](#מה-המערכת-עושה)
2. [קבצים](#קבצים)
3. [התקנה מהירה](#התקנה-מהירה)
4. [איך להריץ](#איך-להריץ)
5. [קובץ הגדרות INI](#קובץ-הגדרות-ini)
6. [מה נאסף בדוח](#מה-נאסף-בדוח)
7. [היסטוריה ולוגים](#היסטוריה-ולוגי)
8. [דשבורד הניתוח (Viewer)](#דשבורד-הניתוח-viewer)
9. [תור טיפול קריטי (4×RAM)](#תור-טיפול-קריטי-4ram)
10. [שליחת מייל](#שליחת-מייל)
11. [פתרון תקלות](#פתרון-תקלות)
12. [הערות אבטחה](#הערות-אבטחה)

---

## מה המערכת עושה

### חלק A – איסוף (Technician / שטח)
- קולט פרטי מזהה: מספר מחשב, לקוח, שם משתמש מפעיל, אימייל
- אוסף נתוני מערכת: מחשב, יצרן, דגם, סידורי, BIOS, OS, Domain, Uptime
- CPU וזיכרון RAM
- דיסקים (נפח, בשימוש, פנוי, אחוז פנוי, סוג מדיה אם זמין)
- רשת בסיסית + בדיקת קישוריות אופציונלית (Google DNS / Cloudflare)
- מזהה תקלות לפי ספי אחוזים ו-GB מקובץ INI
- שומר שורה להיסטוריה מרכזית (`DiskReports_History.csv`)
- שומר לוג שלבים (`DiskReport_Log.csv`)
- אופציונלי: פותח דוח HTML גולמי לפי INI

### חלק B – ניתוח (משרד / ניהול)
- קורא את קובץ ההיסטוריה
- מציג דשבורד HTML מודרני (כהה / בהיר)
- סינונים לפי סטטוס, מחשב, לקוח, משתמש, טווח תאריכים
- תובנות: משתמשים פעילים, מגמות מילוי, שינויים חדים
- **תור טיפול קריטי** לפי מצב אחרון של כל מחשב ונוסחת 4×RAM

---

## קבצים

| קובץ | תפקיד |
|------|--------|
| `DiskReport.ps1` | סקריפט איסוף הנתונים |
| `DiskReport.bat` | מפעיל את האיסוף (לחיצה כפולה) |
| `DiskReport.ini` | הגדרות |
| `DiskReport_Viewer.ps1` | סקריפט ניתוח / דשבורד |
| `DiskReport_Viewer.bat` | מפעיל את הניתוח |
| `DiskReports_History.csv` | היסטוריית כל הבדיקות (נוצר אוטומטית) |
| `DiskReport_Log.csv` | לוג שלבים וזמנים (נוצר אוטומטית) |
| `DiskReport_Analysis.html` | דשבורד ניתוח (שם קבוע, נדרס בכל הרצה) |

כל הקבצים צריכים לשבת **באותה תיקייה**.

---

## התקנה מהירה

1. צור תיקייה, למשל: `D:\PC_Info\`
2. העתק אליה את כל הקבצים מהטבלה למעלה
3. ודא ש-PowerShell מאפשר הרצה מקומית:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
   (או להריץ רק דרך ה-BAT שכבר משתמש ב-`-ExecutionPolicy Bypass`)

---

## איך להריץ

### איסוף במחשב קצה
לחיצה כפולה:
```text
DiskReport.bat
```

או מ-PowerShell:
```powershell
cd D:\PC_Info
.\DiskReport.bat
```

החלון נסגר אוטומטית בסוף.

### ניתוח היסטוריה
```text
DiskReport_Viewer.bat
```

נוצר/מתעדכן הקובץ:
```text
DiskReport_Analysis.html
```
ונפתח בדפדפן.

---

## קובץ הגדרות INI

`DiskReport.ini` לדוגמה:

```ini
[General]
EmailTo=rahimi_e@tel-aviv.gov.il
SubjectPrefix=Maintenance - Cleanup -
CompanyName=Tel Aviv Municipality

[Thresholds]
LowPercent=15
WarningPercent=30
MinFreeGB=10
CriticalFreeGB=5

[Display]
ProgressMode=formal
ShowHtmlReport=0

[Network]
EnableNetworkCheck=1
```

### הסבר שדות

| מקטע | שדה | משמעות |
|------|-----|--------|
| General | `EmailTo` | כתובת היעד הקבועה למייל מהמערכת |
| General | `SubjectPrefix` | קידומת לנושא המייל |
| General | `CompanyName` | שם הארגון בדוחות |
| Thresholds | `LowPercent` | מתחת לזה = Critical (אחוז פנוי) |
| Thresholds | `WarningPercent` | מתחת לזה = Warning |
| Thresholds | `MinFreeGB` | מתחת לזה = Warning (GB) |
| Thresholds | `CriticalFreeGB` | מתחת לזה = Critical (GB) |
| Display | `ProgressMode` | `formal` או `fun` |
| Display | `ShowHtmlReport` | `0` = לא לפתוח HTML באיסוף, `1` = לפתוח |
| Network | `EnableNetworkCheck` | `1` = Ping ל-8.8.8.8 ו-1.1.1.1 |

---

## מה נאסף בדוח

- Computer Number / Client Name / User Name / User Email
- Computer Name, Logged-in User
- Manufacturer, Model, Serial, BIOS
- OS, Domain, Uptime
- CPU (שם, ליבות, Logical, Max Clock)
- RAM (Total / Used / Free)
- דיסקים לוגיים + ניסיון זיהוי SSD/HDD
- IP, MAC, Gateway, DNS
- תוצאות Connectivity (אם הופעל)
- זמני התחלה/סיום ומשך שלבים
- סטטוס כללי: OK / Warning / Critical

---

## היסטוריה ולוגים

### `DiskReports_History.csv`
שורה אחת לכל הרצת איסוף.  
משמש את ה-Viewer לניתוח לאורך זמן.

**כתיבה מחוזקת (v1.6.3+)**
- נעילת קובץ
- ניסיונות חוזרים (מתאים גם להרצות במקביל)
- Escape לשדות CSV
- הודעה עם נתיב מלא ומספר שורות אחרי שמירה

### `DiskReport_Log.csv`
לוג טכני של שלבים (Input, SystemInfo, Storage, Network, Finalize) עם משכי זמן.

---

## דשבורד הניתוח (Viewer)

קובץ פלט קבוע:
```text
DiskReport_Analysis.html
```

### יכולות
- מצב **כהה / בהיר**
- כרטיסי סיכום (Records / Critical / Warning / Treatment queue)
- סינון לפי:
  - Status
  - Computer #
  - Client
  - User Name
  - Computer Name
  - טווח תאריכים
- ספירות מתעדכנות לפי הסינון
- Top Users
- תור טיפול קריטי לפי נוסחת 4×RAM
- הצגת גרסת Viewer + טווח התאריכים שב-CSV

---

## תור טיפול קריטי (4×RAM)

הניתוח מתבסס על **הרשומה האחרונה של כל מחשב** (לא על משתמש מפעיל).

### נוסחה
```text
Required Free GB = Total RAM GB × 4
```

### דרגות חומרה

| דרגה | תנאי | עדיפות |
|------|------|--------|
| EMPTY | Free ≤ 0 GB | הגבוהה ביותר |
| CRITICAL-LOW | Free < 5 GB | גבוהה מאוד |
| SEVERE | Free < 25% מהנדרש (4×RAM) | גבוהה |
| HIGH | Free < 50% מהנדרש | בינונית-גבוהה |
| WATCH | Free < הנדרש המלא | בינונית |
| OK | Free ≥ הנדרש | לא מוצג בתור |

**מיון התור:** חומרה גבוהה קודם → ואז מקום פנוי נמוך יותר קודם.

---

## שליחת מייל

בגרסת האיסוף, אם מופעל מנגנון מייל מהדוח:
- היעד הקבוע מגיע מ-`EmailTo` ב-INI
- נושא לפי `SubjectPrefix` + מספר מחשב

> הערה: תלוי ב-Outlook/לקוח המייל המוגדר במערכת.

---

## פתרון תקלות

### PowerShell לא מריץ מהתיקייה הנוכחית
השתמש ב:
```powershell
.\DiskReport.bat
```
ולא רק `DiskReport.bat` בתוך PowerShell.

### CSV לא מתעדכן
1. בדוק בהודעת הסיום את השורה:
   ```text
   History file: ...
   History lines now: ...
   ```
2. ודא שהקובץ שאתה פותח הוא **באותה תיקייה של ה-PS1**
3. סגור Excel אם הקובץ פתוח בו (עלול לנעול כתיבה)
4. עדכן ל-`DiskReport.ps1` v1.6.3+

### Viewer מציג 0 רשומות
1. ודא שקיים `DiskReports_History.csv` עם נתונים
2. השתמש ב-Viewer v1.5.0+ (טעינת נתונים ב-Base64)
3. רענן את `DiskReport_Analysis.html` אחרי הרצה חדשה של ה-Viewer

### מצב בהיר לא מתחלף
עדכן ל-Viewer v1.5.0+. אם עדיין לא: F12 → Console ובדוק שגיאות JS.

### HTML נפתח גם כש-ShowHtmlReport=0
עדכן את `DiskReport.ps1` ואת ה-INI. ברירת המחדל המומלצת:
```ini
ShowHtmlReport=0
```

---

## הערות אבטחה

- הסקריפטים קוראים מידע מערכת מקומי בלבד (WMI/CIM)
- אין העלאה לענן מצד הסקריפט
- בדיקת רשת (אם פעילה) היא Ping בסיסי לכתובות ציבוריות ידועות
- מומלץ לשמור את תיקיית הכלי בנתיב ארגוני מבוקר
- קבצי CSV עלולים להכיל מזהי מחשבים / משתמשים – טפלו בהם לפי מדיניות הארגון

---

## זרימת עבודה מומלצת

1. טכנאי מריץ `DiskReport.bat` במחשב קצה
2. הנתונים נשמרים ל-`DiskReports_History.csv` (בתיקייה משותפת אם הוגדרה)
3. במשרד מריצים `DiskReport_Viewer.bat`
4. נפתח `DiskReport_Analysis.html`
5. עובדים לפי **Critical Treatment Queue**

---

## תמיכה בגרסאות Windows

- מיועד ל-Windows עם PowerShell 5.1+
- חלק מהשדות (למשל `Get-PhysicalDisk`, `Get-NetIPConfiguration`) תלויים בגרסת מערכת/מודולים

---

*Disk Report System – internal maintenance utility*
