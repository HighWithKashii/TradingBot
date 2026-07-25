# BeanFocus – Whoop-Style Fitness & Recovery App

Native iOS App (SwiftUI, iOS 17+), die Fitness-, Erholungs- und Stresswerte aus
HealthKit auswertet und im dunklen, Whoop-inspirierten UI-Design darstellt.

## Projektstruktur

```
BeanFocus.xcodeproj/        Xcode-Projekt (generiert, siehe unten)
BeanFocus/
  App/                      App-Einstieg, SwiftData-Container, HealthKit/Mock-Umschaltung
  Models/                   RecoveryScore, StrainScore, SleepSession, StressSample, JournalEntry (SwiftData), DailyMetrics (SwiftData)
  Services/                 HealthKitManager, MockHealthDataProvider, Score-Berechnungen, Sleep/Correlation/Notification/Haptics
  ViewModels/                Ein @Observable ViewModel pro Screen
  Views/                    Home, Recovery, Strain, Sleep, Stress, Trends, Journal, Settings + Komponenten
  Extensions/               Farben, Datum, Zahlenformatierung, Haptik
  PreviewContent/           MockData.swift – Beispiel-/Vorschaudaten für alle Screens
scripts/generate_xcodeproj.rb  Regeneriert das .xcodeproj aus dem Source-Baum
```

Architektur: **MVVM** – Views enthalten keine Business-Logik, ViewModels sind
`@Observable`-Klassen, die Services (HealthKit/Mock + Berechnungen) aufrufen.

## Öffnen & Ausführen

1. `BeanFocus.xcodeproj` in Xcode 15+ öffnen.
2. Unter *Signing & Capabilities* dein **Apple Developer Team** auswählen
   (`DEVELOPMENT_TEAM` ist aktuell leer, da mir für diese Session keine
   Team-ID vorliegt). Die HealthKit-Capability inkl. Entitlements-Datei
   (`BeanFocus/Resources/BeanFocus.entitlements`) ist bereits vorkonfiguriert.
3. Build & Run auf Simulator oder Gerät.

Das Projekt wurde ohne direkten Xcode-Zugriff erstellt: Statt die
`project.pbxproj` von Hand zu schreiben, erzeugt
`scripts/generate_xcodeproj.rb` (Ruby-Gem `xcodeproj`) daraus ein valides
Xcode-Projekt. Wenn du Dateien außerhalb von Xcode hinzufügst/entfernst,
kannst du das Skript erneut laufen lassen:

```bash
gem install xcodeproj
ruby scripts/generate_xcodeproj.rb
```

(Wenn du Dateien direkt in Xcode hinzufügst, aktualisiert Xcode das Projekt
selbst – das Skript ist nur für Änderungen außerhalb von Xcode nötig.)

## HealthKit im Simulator – wichtiger Hinweis

Der iOS Simulator hat **keine Sensoren**. Kontinuierliche Herzfrequenz, HRV,
Schlafphasen, SpO2 etc. entstehen dort nicht von selbst. Deshalb:

- **`MockHealthDataProvider`** liefert deterministische, realistische
  Beispieldaten (7/30/90 Tage Recovery/Strain/Sleep/Stress, Workouts,
  Journal-Einträge) – jede View sieht damit vollständig befüllt aus, auch
  ganz ohne HealthKit-Zugriff.
- **`AppEnvironment`** (`BeanFocus/App/AppEnvironment.swift`) entscheidet
  automatisch: Läuft die App im Simulator, wird Mock-Daten verwendet; auf
  einem echten Gerät wird `HealthKitManager` (echtes HealthKit) verwendet.
- In den **Einstellungen** (Profil-Icon oben rechts) kann "Mock-Daten
  verwenden" jederzeit manuell umgeschaltet werden – nützlich für Demos auch
  auf einem echten Gerät ohne Watch-Daten.
- Willst du echte Werte im Simulator testen: In der **Health-App im
  Simulator** (Durchsuchen → z. B. "Herzfrequenz" → Daten hinzufügen) lassen
  sich manuell Beispielwerte eintragen, die `HealthKitManager` dann
  ausliest, wenn Mock-Daten deaktiviert ist.
- Für Live-Herzfrequenz während eines Trainings (Strain-Tab) sowie
  Schlafphasen/HRV in ausreichender Dichte ist ein echtes iPhone + Apple
  Watch nötig.

## Score-Berechnungen (transparent, nicht Whoops proprietärer Algorithmus)

- **Recovery** (`RecoveryCalculator`): 50 % HRV vs. 30-Tage-Baseline, 20 %
  Ruhepuls vs. Baseline, 30 % Schlaf-Performance (Dauer + Effizienz vs.
  Bedarf).
- **Strain** (`StrainCalculator`): Zeit in 5 Herzfrequenzzonen, gewichtet
  nach Zone, auf einer Log-Kurve auf 0–21 komprimiert (ähnlich Whoops
  "je höher, desto schwerer zu steigern"-Charakteristik). Tagesziel skaliert
  mit dem aktuellen Recovery-Wert.
- **Stress** (`StressCalculator`): Instantane HRV im Verhältnis zur
  Baseline → 0–100, mit Zustands-Mapping Ruhig/Ausgeglichen/Gestresst.
- **Schlaf** (`SleepAnalyzer`): Schlafschuld, Konsistenz-Score (Varianz von
  Bett-/Aufwachzeit), empfohlene Schlafenszeit basierend auf Ziel-Aufwachzeit
  und aktuellem Recovery-Bedarf.
- **Korrelationen** (`CorrelationEngine`): Vergleicht Journal-Faktoren eines
  Abends mit dem Recovery-Wert des Folgetags; zusätzlich ein immer
  verfügbarer "< 7h Schlaf"-Insight ganz ohne Journal-Daten.

Alle Formeln sind bewusst einfach und in eigenen, testbaren Services
gekapselt – Gewichtungen lassen sich leicht anpassen, sobald echte
Nutzerdaten zum Kalibrieren vorliegen.

## Offene Punkte / brauche ich von dir

1. **Apple Developer Team-ID** für Code-Signing – bitte in Xcode unter
   *Signing & Capabilities* dein Team auswählen, dann läuft die App auf
   einem echten Gerät.
2. **Bundle Identifier**: aktuell `com.beanfocus.app` (Platzhalter) – sag
   Bescheid, falls du eine andere ID im App Store Connect reserviert hast.
3. **App Icon**: Es ist nur ein leerer 1024×1024-Slot in
   `Assets.xcassets/AppIcon.appiconset` angelegt – noch kein Icon-Bild.
4. Push-Hinweise bei Stress sind aktuell **lokale** Notifications
   (kein Server/APNs nötig). Sag Bescheid, falls du stattdessen
   Remote-Push mit eigenem Backend möchtest.
