#!/usr/bin/env bash
set -euo pipefail

# Mathe-Ueben: Standalone Grosses 1x1 Training
# Usage: bash mathe_ueben.sh [aufgaben_pro_block] [anzahl_bloecke]
# Claude is called via 'claude -p' for exercise generation and evaluation.
# All user interaction happens in this terminal — no interactive Claude session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# === Defaults ===
AUFGABEN=20
BLOECKE=2
DIFF="normal"
DIFF_LABEL="Normal (11-20 x 2-10)"
A_MIN=11
A_MAX=20
B_MIN=2
B_MAX=10

# === Temp dir with cleanup ===
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Background eval tracking ===
EVAL_PID=""
EVAL_BLOCK=""

# === Accumulated results for final analysis ===
ALL_PRACTICE_RESULTS="[]"
ALL_BLOCK_TIMES=""
TOTAL_TIME=0

# === Per-block type array ===
declare -a BLOCK_TYPES=()

# === History ===
HISTORY_DIR="/home/pengg3/work/luca_study/math/history"
TOPIC_KEY="grosses_1x1"
TOPIC_DISPLAY="Grosses 1x1"

load_history() {
    local topic_key="$1"
    local max_sessions="${2:-10}"

    if [[ ! -d "$HISTORY_DIR" ]]; then
        echo "[]"
        return
    fi

    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(ls -1 "$HISTORY_DIR"/*-"${topic_key}.json" 2>/dev/null | sort -r | head -n "$max_sessions")

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi

    local combined="[]"
    for f in "${files[@]}"; do
        local summary
        summary=$(jq '{
            date: .date,
            version: (.version // 1),
            overall_pct: (if .version == 2 then .overall.pct else (.exam.pct // .practice.pct) end),
            overall_grade: (if .version == 2 then .overall.grade else (.exam.grade // null) end),
            overall_time: (if .version == 2 then .overall.total_time_seconds else (.exam.time_seconds // null) end),
            block_types: (.settings.block_types // [.settings.art]),
            practice_pct: (if .version == 2 then .overall.pct else .practice.pct end),
            wrong: (if .version == 2 then [.blocks[].wrong[].q] else ([.exam.wrong[].q] + [.practice.blocks[].wrong[].q]) end)
        }' "$f" 2>/dev/null) || continue
        combined=$(echo "$combined" | jq --argjson s "$summary" '. + [$s]')
    done

    echo "$combined"
}

# === Check dependencies ===
for cmd in jq claude; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Fehler: '$cmd' nicht gefunden. Bitte installieren.${NC}"
        exit 1
    fi
done

# === Grade calculation ===
calc_grade() {
    local pct=$1
    if   ((pct >= 97)); then echo "6"
    elif ((pct >= 90)); then echo "5.5"
    elif ((pct >= 83)); then echo "5"
    elif ((pct >= 75)); then echo "4.5"
    elif ((pct >= 67)); then echo "4"
    elif ((pct >= 58)); then echo "3.5"
    elif ((pct >= 50)); then echo "3"
    else echo "2"
    fi
}

# === Show and wait for any pending background evaluation ===
show_pending_eval() {
    if [[ -n "$EVAL_PID" ]]; then
        if kill -0 "$EVAL_PID" 2>/dev/null; then
            echo -e "\n${DIM}Claude Analyse wird geladen...${NC}"
            wait "$EVAL_PID" 2>/dev/null || true
        fi
        if [[ -f "$TMPDIR/eval_block${EVAL_BLOCK}.txt" ]]; then
            echo -e "\n${BLUE}${BOLD}=== Claude Analyse Block ${EVAL_BLOCK} ===${NC}\n"
            cat "$TMPDIR/eval_block${EVAL_BLOCK}.txt"
            echo ""
        fi
        EVAL_PID=""
        EVAL_BLOCK=""
    fi
}

# ============================================================
# PHASE 1: SETUP
# ============================================================
echo -e "\n${BOLD}Willkommen zum Mathe-Training! (Grosses 1x1)${NC}"
echo -e "Lass uns Multiplikation und Division ueben.\n"

if [[ $# -ge 2 ]]; then
    AUFGABEN=$1
    BLOECKE=$2
elif [[ $# -eq 1 ]]; then
    AUFGABEN=$1
fi

if [[ $# -lt 2 ]]; then
    read -p "Aufgaben pro Block? [10/15/20/30] (20): " ans
    [[ -n "$ans" ]] && AUFGABEN=$ans

    read -p "Anzahl Bloecke? [1/2/3/4] (2): " ans
    [[ -n "$ans" ]] && BLOECKE=$ans

    echo "Aufgabenart?"
    echo "  [g] Gemischt - alle Bloecke (Standard)"
    echo "  [m] Nur Multiplikation - alle Bloecke"
    echo "  [d] Nur Division - alle Bloecke"
    echo "  [f] Fokus-Modus (einige Bloecke gezielt, Rest gemischt)"
    read -p "Auswahl (g): " art_choice

    case "${art_choice:-g}" in
        m*)
            for ((i=0; i<BLOECKE; i++)); do BLOCK_TYPES+=("multiplikation"); done
            ;;
        d*)
            for ((i=0; i<BLOECKE; i++)); do BLOCK_TYPES+=("division"); done
            ;;
        f*)
            echo ""
            echo "Fokus auf welche Rechenart?"
            echo "  [m] Multiplikation"
            echo "  [d] Division"
            read -p "Auswahl (d): " fokus_art
            case "${fokus_art:-d}" in
                m*) FOKUS_TYPE="multiplikation" ;;
                *)  FOKUS_TYPE="division" ;;
            esac

            max_fokus=$((BLOECKE - 1))
            if ((max_fokus < 1)); then max_fokus=1; fi
            read -p "Wie viele der $BLOECKE Bloecke fuer ${FOKUS_TYPE^}? (1, max $max_fokus): " fokus_count
            fokus_count=${fokus_count:-1}
            if ((fokus_count > max_fokus)); then fokus_count=$max_fokus; fi
            if ((fokus_count < 1)); then fokus_count=1; fi

            for ((i=0; i<fokus_count; i++)); do BLOCK_TYPES+=("$FOKUS_TYPE"); done
            for ((i=fokus_count; i<BLOECKE; i++)); do BLOCK_TYPES+=("gemischt"); done
            ;;
        *)
            for ((i=0; i<BLOECKE; i++)); do BLOCK_TYPES+=("gemischt"); done
            ;;
    esac

    echo "Schwierigkeit?"
    echo "  [n] Normal (11-20 x 2-10)"
    echo "  [s] Schwerer (11-25 x 2-12)"
    echo "  [e] Eigene Bereiche festlegen"
    read -p "Auswahl (n): " ans
    case "${ans:-n}" in
        s*) DIFF="schwerer"; DIFF_LABEL="Schwerer (11-25 x 2-12)"
            A_MIN=11; A_MAX=25; B_MIN=2; B_MAX=12 ;;
        e*)
            DIFF="eigene"
            read -p "  Erster Faktor von (11): " a_lo; A_MIN=${a_lo:-11}
            read -p "  Erster Faktor bis (20): " a_hi; A_MAX=${a_hi:-20}
            read -p "  Zweiter Faktor von (2): " b_lo; B_MIN=${b_lo:-2}
            read -p "  Zweiter Faktor bis (10): " b_hi; B_MAX=${b_hi:-10}
            DIFF_LABEL="Eigene (${A_MIN}-${A_MAX} x ${B_MIN}-${B_MAX})" ;;
        *)  DIFF="normal"; DIFF_LABEL="Normal (11-20 x 2-10)"
            A_MIN=11; A_MAX=20; B_MIN=2; B_MAX=10 ;;
    esac
fi

# Fill BLOCK_TYPES with default if not set (e.g. when args provided)
if [[ ${#BLOCK_TYPES[@]} -eq 0 ]]; then
    for ((i=0; i<BLOECKE; i++)); do BLOCK_TYPES+=("gemischt"); done
fi

# Build display label for block types
BLOCK_TYPES_LABEL=""
all_same=true
for ((i=1; i<${#BLOCK_TYPES[@]}; i++)); do
    if [[ "${BLOCK_TYPES[$i]}" != "${BLOCK_TYPES[0]}" ]]; then all_same=false; break; fi
done
if $all_same; then
    case "${BLOCK_TYPES[0]}" in
        gemischt) BLOCK_TYPES_LABEL="Gemischt (alle Bloecke)" ;;
        multiplikation) BLOCK_TYPES_LABEL="Nur Multiplikation (alle Bloecke)" ;;
        division) BLOCK_TYPES_LABEL="Nur Division (alle Bloecke)" ;;
    esac
else
    BLOCK_TYPES_LABEL="Fokus: "
    for ((i=0; i<${#BLOCK_TYPES[@]}; i++)); do
        if ((i > 0)); then BLOCK_TYPES_LABEL+=", "; fi
        BLOCK_TYPES_LABEL+="Block $((i+1))=${BLOCK_TYPES[$i]^}"
    done
fi

echo -e "\n${BLUE}Einstellungen:${NC}"
echo "  Aufgaben pro Block: $AUFGABEN"
echo "  Anzahl Bloecke:     $BLOECKE"
echo "  Aufgabenart:        $BLOCK_TYPES_LABEL"
echo "  Schwierigkeit:      $DIFF_LABEL"

# ============================================================
# PHASE 2: GENERATE ALL EXERCISES VIA CLAUDE
# ============================================================
echo -e "\n${YELLOW}Claude generiert Aufgaben...${NC}\n"

# Build per-block type instructions
BLOCK_TYPE_INSTRUCTIONS=""
for ((i=0; i<BLOECKE; i++)); do
    BLOCK_TYPE_INSTRUCTIONS+="- Block $((i+1)): ${BLOCK_TYPES[$i]}"$'\n'
done

GENERATE_PROMPT="Du bist ein Mathe-Lehrer. Generiere Uebungsaufgaben fuer das Grosse 1x1 (Klasse 4, Schweizer Schule).

Einstellungen:
- Aufgaben pro Block: ${AUFGABEN}
- Anzahl Bloecke: ${BLOECKE}
- Erster Faktor (A): ${A_MIN} bis ${A_MAX}
- Zweiter Faktor (B): ${B_MIN} bis ${B_MAX}

Aufgabenart pro Block:
${BLOCK_TYPE_INSTRUCTIONS}
Regeln fuer Zahlenbereiche:
- A wird zufaellig aus [${A_MIN}..${A_MAX}] gewaehlt
- B wird zufaellig aus [${B_MIN}..${B_MAX}] gewaehlt

Regeln fuer Aufgaben:
- Multiplikation: Format 'A x B', Antwort = A*B
- Division: Berechne C = A*B, dann entweder 'C : A' (Antwort=B) oder 'C : B' (Antwort=A). Ganzzahlige Ergebnisse!
- Gemischt: ca. 50/50 Multiplikation und Division
- Verwende 'x' fuer Multiplikation und ':' fuer Division

Wichtig:
- Keine doppelten Aufgaben innerhalb eines Blocks
- Gute Abwechslung ueber verschiedene Reihen (11er bis 20er bzw. 25er)
- Beachte die Aufgabenart pro Block (gemischt/multiplikation/division)

Antworte NUR mit validem JSON in diesem Format (kein anderer Text, keine Erklaerung):
{
  \"blocks\": [
    [{\"q\": \"14 x 7\", \"a\": 98}, ...],
    [{\"q\": \"180 : 15\", \"a\": 12}, ...]
  ]
}

blocks hat genau ${BLOECKE} Arrays mit je ${AUFGABEN} Aufgaben."

# Call Claude to generate exercises
if ! claude -p "$GENERATE_PROMPT" > "$TMPDIR/generated_raw.txt" 2>"$TMPDIR/generate_err.txt"; then
    echo -e "${RED}Fehler bei der Aufgaben-Generierung. Claude Ausgabe:${NC}"
    cat "$TMPDIR/generate_err.txt"
    exit 1
fi

# Extract JSON (Claude might wrap it in markdown code blocks)
sed -n '/^{/,/^}/p' "$TMPDIR/generated_raw.txt" > "$TMPDIR/generated.json"

# Validate JSON
if ! jq empty "$TMPDIR/generated.json" 2>/dev/null; then
    # Try extracting from code block
    sed -n '/```json/,/```/p' "$TMPDIR/generated_raw.txt" | sed '1d;$d' > "$TMPDIR/generated.json"
    if ! jq empty "$TMPDIR/generated.json" 2>/dev/null; then
        echo -e "${RED}Fehler: Claude hat kein gueltiges JSON zurueckgegeben.${NC}"
        echo "Rohe Ausgabe:"
        cat "$TMPDIR/generated_raw.txt"
        exit 1
    fi
fi

# Extract blocks into separate files
for ((b=0; b<BLOECKE; b++)); do
    jq ".blocks[$b]" "$TMPDIR/generated.json" > "$TMPDIR/block$((b+1)).json"
    block_len=$(jq 'length' "$TMPDIR/block$((b+1)).json")
    if [[ "$block_len" == "null" ]] || [[ "$block_len" -lt 1 ]]; then
        echo -e "${RED}Fehler: Block $((b+1)) ist leer oder ungueltig.${NC}"
        exit 1
    fi
done

echo -e "${GREEN}Aufgaben bereit! ${BLOECKE} Bloecke generiert.${NC}"

# ============================================================
# PHASE 3: PRACTICE BLOCKS
# ============================================================
for ((b=1; b<=BLOECKE; b++)); do
    exercises_file="$TMPDIR/block${b}.json"
    total=$(jq 'length' "$exercises_file")
    block_type="${BLOCK_TYPES[$((b-1))]}"
    block_type_display="${block_type^}"

    # Pre-parse exercises into arrays for zero-latency presentation
    readarray -t questions < <(jq -r '.[].q' "$exercises_file")
    readarray -t answers < <(jq -r '.[].a' "$exercises_file")

    echo -e "\n${BOLD}=== Block ${b}/${BLOECKE} (${total} Aufgaben, ${block_type_display}) ===${NC}\n"

    # Interactive exercise presentation
    > "$TMPDIR/results_block${b}.jsonl"
    BLOCK_START_TIME=$(date +%s)
    for ((i=0; i<total; i++)); do
        q="${questions[$i]}"
        a="${answers[$i]}"
        read -p "Aufgabe $((i+1))/${total}: ${q} = " user_ans

        # Re-ask once if empty
        if [[ -z "$user_ans" ]]; then
            echo "Bitte gib deine Antwort ein:"
            read -p "> " user_ans
        fi

        # Write result as jsonl (no jq in loop)
        printf '{"q":"%s","a":%s,"user":"%s"}\n' "$q" "$a" "${user_ans:-}" >> "$TMPDIR/results_block${b}.jsonl"
    done
    BLOCK_END_TIME=$(date +%s)
    BLOCK_ELAPSED=$((BLOCK_END_TIME - BLOCK_START_TIME))
    BLOCK_MINS=$((BLOCK_ELAPSED / 60))
    BLOCK_SECS=$((BLOCK_ELAPSED % 60))
    TOTAL_TIME=$((TOTAL_TIME + BLOCK_ELAPSED))

    # Convert jsonl to JSON array
    jq -s '.' "$TMPDIR/results_block${b}.jsonl" > "$TMPDIR/results_block${b}.json"
    block_results=$(cat "$TMPDIR/results_block${b}.json")

    echo -e "\n--- Block ${b} abgeschlossen! ---"

    # === Quick bash-side score (instant) ===
    correct=0
    wrong_list=""

    echo -e "\n${BOLD}=== Block ${b} Ergebnis (${block_type_display}) ===${NC}\n"
    printf "%-4s %-18s %-14s %-8s %s\n" "Nr" "Aufgabe" "Deine Antwort" "Richtig" ""
    printf "%-4s %-18s %-14s %-8s %s\n" "---" "-----------------" "-------------" "-------" "-------"

    for ((i=0; i<total; i++)); do
        q="${questions[$i]}"
        a="${answers[$i]}"
        u=$(jq -r ".[$i].user" "$TMPDIR/results_block${b}.json")

        if [[ "$u" == "$a" ]]; then
            correct=$((correct + 1))
            printf "%-4s %-18s %-14s %-8s " "$((i+1))" "$q" "$u" "$a"
            echo -e "${GREEN}Richtig${NC}"
        else
            printf "%-4s %-18s %-14s %-8s " "$((i+1))" "$q" "${u:-—}" "$a"
            echo -e "${RED}Falsch${NC}"
            wrong_list="${wrong_list}\n  - ${q} = ${a} (du hast ${u:-nichts} geschrieben)"
        fi
    done

    pct=$((correct * 100 / total))
    echo -e "\nErgebnis: ${BOLD}${correct}/${total} richtig (${pct}%)${NC}"
    echo -e "Zeit: ${BLOCK_MINS} Minuten und ${BLOCK_SECS} Sekunden ($(( BLOCK_ELAPSED / total ))s pro Aufgabe)"
    [[ -n "$wrong_list" ]] && echo -e "\n${RED}Falsche Antworten:${NC}${wrong_list}"

    # Accumulate results and timing
    ALL_PRACTICE_RESULTS=$(echo "$ALL_PRACTICE_RESULTS" | jq --argjson br "$block_results" '. + $br')
    ALL_BLOCK_TIMES="${ALL_BLOCK_TIMES}Block ${b} (${block_type_display}): ${BLOCK_MINS}m ${BLOCK_SECS}s (${BLOCK_ELAPSED}s total, $(( BLOCK_ELAPSED / total ))s pro Aufgabe)\n"

    # === Start Claude evaluation in background ===
    EVAL_BLOCK=$b
    EVAL_PROMPT="Du bist ein freundlicher Mathe-Lehrer fuer Klasse 4 (Schweizer Schule). Antworte auf Deutsch.
Verwende ae/oe/ue statt Umlaute.

Hier sind die Ergebnisse von Uebungsblock ${b} (${block_type_display}):
${block_results}

Zeit: ${BLOCK_MINS} Minuten und ${BLOCK_SECS} Sekunden (${BLOCK_ELAPSED}s total, $(( BLOCK_ELAPSED / total ))s pro Aufgabe)

Gib eine kurze Analyse (5-8 Zeilen):
1. Welche Reihen waren schwierig? (z.B. 17er, 19er Reihe)
2. War Multiplikation oder Division schwieriger?
3. Gab es Fluechtigkeitsfehler (Antwort nur um 1-2 daneben)?
4. Geschwindigkeit: unter 10s/Aufgabe=sehr schnell, 10-15s=gut, 15-20s=ok, ueber 20s=mehr Uebung noetig
5. 1-2 konkrete Tipps zur Verbesserung

Kein Markdown, nur Klartext fuer Terminal-Ausgabe."

    claude -p "$EVAL_PROMPT" > "$TMPDIR/eval_block${b}.txt" 2>/dev/null &
    EVAL_PID=$!

    # === User choice ===
    if ((b < BLOECKE)); then
        # Check for wrong exercises
        wrong_count=$(echo "$block_results" | jq '[.[] | select(.user != (.a | tostring))] | length')

        echo ""
        echo "Was moechtest du tun?"
        echo "  [w] Weiter zum naechsten Block"
        [[ "$wrong_count" -gt 0 ]] && echo "  [f] Falsche Aufgaben nochmal ueben (${wrong_count} Aufgaben)"
        echo "  [a] Claude Analyse anzeigen (falls bereit)"
        read -p "Auswahl (w): " choice

        case "${choice:-w}" in
            a)
                show_pending_eval
                # Ask again after showing eval
                echo "Was moechtest du tun?"
                echo "  [w] Weiter zum naechsten Block"
                [[ "$wrong_count" -gt 0 ]] && echo "  [f] Falsche Aufgaben nochmal ueben"
                read -p "Auswahl (w): " choice2
                choice="${choice2:-w}"
                ;;
        esac

        case "${choice:-w}" in
            f)
                if ((wrong_count > 0)); then
                    # Extract wrong exercises
                    wrong_exercises=$(echo "$block_results" | jq '[.[] | select(.user != (.a | tostring)) | {q: .q, a: .a}]')
                    wrong_total=$(echo "$wrong_exercises" | jq 'length')

                    readarray -t wq < <(echo "$wrong_exercises" | jq -r '.[].q')
                    readarray -t wa < <(echo "$wrong_exercises" | jq -r '.[].a')

                    echo -e "\n${BOLD}=== Block ${b} Wiederholung (${wrong_total} Aufgaben) ===${NC}\n"

                    for ((i=0; i<wrong_total; i++)); do
                        read -p "Aufgabe $((i+1))/${wrong_total}: ${wq[$i]} = " retry_ans
                        if [[ "${retry_ans:-}" == "${wa[$i]}" ]]; then
                            echo -e "  ${GREEN}Richtig!${NC}"
                        else
                            echo -e "  ${RED}Falsch — richtige Antwort: ${wa[$i]}${NC}"
                        fi
                    done
                    echo ""
                fi
                ;;
        esac
    else
        # Last block — show eval
        show_pending_eval
    fi
done

# ============================================================
# PHASE 4: OVERALL RESULT & FINAL ANALYSIS
# ============================================================

# Show any remaining pending eval
show_pending_eval

# Calculate overall stats
overall_total=$(echo "$ALL_PRACTICE_RESULTS" | jq 'length')
overall_correct=$(echo "$ALL_PRACTICE_RESULTS" | jq '[.[] | select(.user == (.a | tostring))] | length')
overall_pct=$((overall_correct * 100 / overall_total))
overall_grade=$(calc_grade $overall_pct)
total_mins=$((TOTAL_TIME / 60))
total_secs=$((TOTAL_TIME % 60))

echo -e "\n${BOLD}============================================="
echo -e "         GESAMTERGEBNIS"
echo -e "=============================================${NC}\n"
echo -e "Punkte: ${BOLD}${overall_correct}/${overall_total} (${overall_pct}%)${NC}"
echo -e "Note:   ${BOLD}${overall_grade}${NC}"
echo -e "Zeit:   ${total_mins} Minuten und ${total_secs} Sekunden"

# === Final analysis via Claude ===
echo -e "\n${YELLOW}Claude analysiert alle Ergebnisse...${NC}\n"

# Load history for progress tracking
HISTORY_JSON=$(load_history "$TOPIC_KEY" 10)
HISTORY_COUNT=$(echo "$HISTORY_JSON" | jq 'length')

if ((HISTORY_COUNT > 0)); then
    HISTORY_SECTION="
=== FRUEHERE SITZUNGEN (${HISTORY_COUNT} Eintraege, neueste zuerst) ===
${HISTORY_JSON}

Bitte fuege einen ausfuehrlichen Abschnitt FORTSCHRITT UND LERNANALYSE hinzu.
Du bist jetzt nicht nur Mathe-Lehrer, sondern auch Lerncoach. Analysiere die
gesamte Lerngeschichte und gib tiefe Einblicke:

7a. LEISTUNGSTREND
   - Zeige die Entwicklung der Noten und Prozente ueber alle Sitzungen
   - Genauigkeit: Wird es besser, schlechter, oder stagniert es?
   - Geschwindigkeit: Wird das Kind schneller?
   - Gibt es ein Plateau? Wenn ja, was koennte helfen es zu durchbrechen?

7b. VERSTECKTE MUSTER UND LERNGEWOHNHEITEN
   - Welche Reihen/Aufgabentypen tauchen IMMER WIEDER als Fehler auf?
     (z.B. 17er Reihe war in 3 von 4 Sitzungen schwach)
   - Gibt es systematische Fehlertypen? (z.B. immer Ziffern vertauscht,
     immer bei Division Probleme, immer bei grossen Zahlen unsicher)
   - Zeigt das Kind bestimmte Lernmuster? (z.B. starker Start aber
     Konzentration laesst nach, oder umgekehrt: braucht Aufwaermphase)

7c. LERNQUALITAET UND FORTSCHRITTSEINSCHAETZUNG
   - Wie nachhaltig ist das Lernen? Werden einmal gelernte Reihen behalten?
   - Welche Reihen/Bereiche sind wirklich gefestigt (konstant gut)?
   - Welche sind fragil (mal gut, mal schlecht)?
   - Gesamteinschaetzung: Wo steht das Kind im Vergleich zum Ziel
     (sicheres Beherrschen des Grossen 1x1)?

7d. KONKRETER UEBUNGSPLAN
   - Was sollte das Kind als Naechstes ueben? (max 2-3 Fokus-Bereiche)
   - Wie oft und wie lange pro Woche ueben?
   - Welche Schwierigkeit empfehlen?
   - Ein konkretes, messbares Ziel fuer die naechste Sitzung
     (z.B. '17er Reihe: mindestens 80% richtig' oder 'Note 5')
   - Langfristiges Ziel: Was waere in 2-4 Wochen realistisch erreichbar?

Schreibe diesen Abschnitt ausfuehrlich und konkret. Benutze die Daten aus
den frueheren Sitzungen um ECHTE Muster zu zeigen, nicht nur Zahlen zu
wiederholen. Das Kind und die Eltern sollen verstehen WAS und WARUM,
nicht nur WIE VIEL.
"
else
    HISTORY_SECTION=""
fi

# Build block type summary for analysis
BLOCK_TYPE_SUMMARY=""
for ((b=0; b<BLOECKE; b++)); do
    BLOCK_TYPE_SUMMARY+="Block $((b+1)): ${BLOCK_TYPES[$b]^}"$'\n'
done

FINAL_PROMPT="Du bist ein freundlicher Mathe-Lehrer fuer Klasse 4 (Schweizer Schule). Antworte auf Deutsch.
Verwende ae/oe/ue statt Umlaute. Kein Markdown, nur Klartext fuer Terminal-Ausgabe.

=== ALLE ERGEBNISSE ===

${BLOECKE} Bloecke mit je ${AUFGABEN} Aufgaben:
${ALL_PRACTICE_RESULTS}

Block-Typen:
${BLOCK_TYPE_SUMMARY}
Zeiten:
$(echo -e "$ALL_BLOCK_TIMES")
Gesamtergebnis: ${overall_correct}/${overall_total} (${overall_pct}%), Note ${overall_grade}
Gesamtzeit: ${total_mins}m ${total_secs}s

=== ANALYSE-AUFTRAG ===

Erstelle eine ausfuehrliche Analyse mit folgenden Abschnitten:

1. FEHLERANALYSE NACH REIHE
   - Zaehle Fehler pro Reihe (11er, 12er, ... 20er/25er Reihe)
   - Welche Reihen sind die staerksten, welche die schwaechsten?

2. FEHLERANALYSE NACH AUFGABENART
   - Vergleiche Fehlerrate Multiplikation vs Division
   - Welche ist schwieriger?
   - Beruecksichtige die Block-Typen (manche Bloecke waren nur eine Rechenart)

3. FEHLERTYPEN
   - Verrechnet um 1-2 (Fluechtigkeitsfehler)
   - Verwechslung (Ziffern vertauscht, z.B. 136 statt 163)
   - Falsche Reihe (falsche Multiplikationstabelle verwendet)
   - Grober Fehler (weit daneben)

4. GESCHWINDIGKEIT
   - Unter 10s/Aufgabe: Sehr schnell
   - 10-15s: Gut
   - 15-20s: OK
   - Ueber 20s: Mehr Uebung noetig
   - Vergleiche die Geschwindigkeit zwischen den Bloecken

5. EMPFEHLUNGEN (3-5 konkrete, kindgerechte Tipps)

6. ZUSAMMENFASSUNG
   Gesamt: ${overall_correct}/${overall_total} (${overall_pct}%) ueber ${BLOECKE} Bloecke
   Note: ${overall_grade}
   Staerkste Reihen: [Liste]
   Schwaechste Reihen: [Liste]
${HISTORY_SECTION}"

ANALYSIS_TEXT=$(claude -p "$FINAL_PROMPT" 2>/dev/null)
echo "$ANALYSIS_TEXT"

# ============================================================
# PHASE 5: SAVE SESSION HISTORY
# ============================================================
mkdir -p "$HISTORY_DIR"

SESSION_TS=$(date +%Y-%m-%d-%H%M%S)
HISTORY_FILE="${HISTORY_DIR}/${SESSION_TS}-${TOPIC_KEY}.json"

# Build blocks JSON array with per-block stats
BLOCKS_JSON="[]"
for ((b=1; b<=BLOECKE; b++)); do
    if [[ -f "$TMPDIR/results_block${b}.json" ]]; then
        block_data=$(cat "$TMPDIR/results_block${b}.json")
        block_total=$(echo "$block_data" | jq 'length')
        block_correct=$(echo "$block_data" | jq '[.[] | select(.user == (.a | tostring))] | length')
        block_pct=$((block_correct * 100 / block_total))
        block_wrong=$(echo "$block_data" | jq '[.[] | select(.user != (.a | tostring)) | {q, a, user}]')
        block_type="${BLOCK_TYPES[$((b-1))]}"

        BLOCKS_JSON=$(echo "$BLOCKS_JSON" | jq \
            --argjson bn "$b" \
            --arg bt "$block_type" \
            --argjson btotal "$block_total" \
            --argjson bc "$block_correct" \
            --argjson bp "$block_pct" \
            --argjson bw "$block_wrong" \
            '. + [{"block_nr": $bn, "type": $bt, "total": $btotal, "correct": $bc, "pct": $bp, "wrong": $bw}]')
    fi
done

# Build block_types JSON array
BLOCK_TYPES_JSON=$(printf '%s\n' "${BLOCK_TYPES[@]}" | jq -R . | jq -s .)

# Write session JSON
jq -n \
    --argjson version 2 \
    --arg ts "$(date -Iseconds)" \
    --arg date "$(date +%Y-%m-%d)" \
    --arg script "mathe_ueben" \
    --arg topic "$TOPIC_KEY" \
    --arg topic_display "$TOPIC_DISPLAY" \
    --argjson aufgaben "$AUFGABEN" \
    --argjson bloecke "$BLOECKE" \
    --argjson block_types "$BLOCK_TYPES_JSON" \
    --arg diff "$DIFF" \
    --argjson blocks "$BLOCKS_JSON" \
    --argjson overall_total "$overall_total" \
    --argjson overall_correct "$overall_correct" \
    --argjson overall_pct "$overall_pct" \
    --arg overall_grade "$overall_grade" \
    --argjson total_time "$TOTAL_TIME" \
    --arg analysis "$ANALYSIS_TEXT" \
    '{
        version: $version,
        timestamp: $ts,
        date: $date,
        script: $script,
        topic: $topic,
        topic_display: $topic_display,
        settings: {
            aufgaben_pro_block: $aufgaben,
            bloecke: $bloecke,
            block_types: $block_types,
            schwierigkeit: $diff
        },
        blocks: $blocks,
        overall: {
            total: $overall_total,
            correct: $overall_correct,
            pct: $overall_pct,
            grade: $overall_grade,
            total_time_seconds: $total_time
        },
        analysis: $analysis
    }' > "$HISTORY_FILE"

echo -e "\n${DIM}Ergebnisse gespeichert: ${HISTORY_FILE}${NC}"
echo -e "\n${GREEN}${BOLD}Gut gemacht! Bis zum naechsten Mal!${NC}\n"
