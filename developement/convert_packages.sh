#!/usr/bin/env bash
set -euo pipefail

# Debian 13 (trixie) Paketliste als gz
URL="https://packages.debian.org/trixie/allpackages?format=txt.gz"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/deb-pkgmap"
GZ_FILE="$CACHE_DIR/trixie-allpackages.txt.gz"
NAMES_FILE="$CACHE_DIR/trixie-packagenames.txt"

mkdir -p "$CACHE_DIR"

die() { echo "Fehler: $*" >&2; exit 1; }

download_list() {
  local tmp="$GZ_FILE.tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$tmp" || die "Download fehlgeschlagen (curl)"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$URL" || die "Download fehlgeschlagen (wget)"
  else
    die "Benötige curl oder wget."
  fi
  mv -f "$tmp" "$GZ_FILE"
}

refresh_cache() {
  if [[ ! -s "$GZ_FILE" ]]; then
    download_list
    return
  fi
  if [[ -n "$(find "$GZ_FILE" -mtime +1 -print -quit 2>/dev/null || true)" ]]; then
    download_list
  fi
}

build_names_index() {
  local tmp="$NAMES_FILE.tmp"
  gzip -dc "$GZ_FILE" | awk '{print $1}' | sort -u > "$tmp"
  mv -f "$tmp" "$NAMES_FILE"
}

ensure_index() {
  refresh_cache
  if [[ ! -s "$NAMES_FILE" || "$NAMES_FILE" -ot "$GZ_FILE" ]]; then
    build_names_index
  fi
}

escape_ere() {
  printf '%s' "$1" | sed -e 's/[].[^$\\|?*+(){}]/\\&/g'
}

strip_versionish() {
  local s="$1"
  s="${s%%:*}"
  printf '%s' "$s"
}

###############################################################################
# FILTERLOGIK (wie zuvor)
###############################################################################
best_match_for() {
  local q="$1"
  local exact_exists=0
  grep -Fxq "$q" "$NAMES_FILE" && exact_exists=1

  # <basis>-<zahl>-<suffix>  (gcc-11-base -> gcc-12-base)
  if [[ "$q" =~ ^(.+)-([0-9]+)-(.+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local want="${BASH_REMATCH[2]}"
    local suffix="${BASH_REMATCH[3]}"
    local re="^$(escape_ere "$base")-[0-9]+-$(escape_ere "$suffix")$"

    local cand
    cand="$(grep -E "$re" "$NAMES_FILE" || true)"
    if [[ -n "$cand" ]]; then
      if [[ "$exact_exists" -eq 1 ]]; then
        local out
        out="$(printf '%s\n' "$cand" | awk -v b="$base" -v w="$want" -v s="$suffix" '
          function v(n, tmp){
            tmp=n
            sub("^"b"-","",tmp)
            sub("-"s"$","",tmp)
            return tmp+0
          }
          BEGIN{bestV=1e18; best=""}
          {x=v($0); if(x>w && x<bestV){bestV=x; best=$0}}
          END{if(best!="") print best}
        ')"
        [[ -n "$out" ]] && { echo "$out"; return 0; }
      else
        local out
        out="$(printf '%s\n' "$cand" | awk -v b="$base" -v w="$want" -v s="$suffix" '
          function v(n, tmp){
            tmp=n
            sub("^"b"-","",tmp)
            sub("-"s"$","",tmp)
            return tmp+0
          }
          BEGIN{upV=1e18; up=""; downV=-1; down=""}
          {x=v($0); if(x>=w && x<upV){upV=x; up=$0}; if(x<w && x>downV){downV=x; down=$0}}
          END{if(up!="") print up; else if(down!="") print down}
        ')"
        [[ -n "$out" ]] && { echo "$out"; return 0; }
      fi
    fi
  fi

  # <prefix><dottedVersion>-<suffix> (php8.2-bz2 -> php8.4-bz2)
  if [[ "$q" == *-* ]]; then
    local prefix="${q%-*}"
    local suffix="${q##*-}"

    if [[ "$prefix" =~ ^(.+?)([0-9]+(\.[0-9]+)+)$ ]]; then
      local base="${BASH_REMATCH[1]}"
      local wantver="${BASH_REMATCH[2]}"

      local re="^$(escape_ere "$base")[0-9]+(\.[0-9]+)+-$(escape_ere "$suffix")$"
      local cand
      cand="$(grep -E "$re" "$NAMES_FILE" || true)"

      if [[ -n "$cand" ]]; then
        if [[ "$exact_exists" -eq 1 ]]; then
          local out
          out="$(printf '%s\n' "$cand" | awk -v b="$base" -v s="$suffix" '
            function score(ver,    i,n,a,sc){
              n=split(ver,a,"\\.")
              sc=0
              for(i=1;i<=n;i++){ sc=sc*1000 + (a[i]+0) }
              return sc
            }
            function v(name, tmp){
              tmp=name
              sub("^"b,"",tmp)
              sub("-"s"$","",tmp)
              return score(tmp)
            }
            BEGIN{best=-1; bestName=""}
            {x=v($0); if(x>best){best=x; bestName=$0}}
            END{if(bestName!="") print bestName}
          ')"
          [[ -n "$out" ]] && { echo "$out"; return 0; }
        else
          local out
          out="$(printf '%s\n' "$cand" | awk -v b="$base" -v w="$wantver" -v s="$suffix" '
            function score(ver,    i,n,a,sc){
              n=split(ver,a,"\\.")
              sc=0
              for(i=1;i<=n;i++){ sc=sc*1000 + (a[i]+0) }
              return sc
            }
            function v(name, tmp){
              tmp=name
              sub("^"b,"",tmp)
              sub("-"s"$","",tmp)
              return score(tmp)
            }
            BEGIN{
              want=score(w)
              upV=1e18; up=""; downV=-1; down=""
            }
            {
              x=v($0)
              if(x>=want && x<upV){upV=x; up=$0}
              if(x<want && x>downV){downV=x; down=$0}
            }
            END{ if(up!="") print up; else if(down!="") print down }
          ')"
          [[ -n "$out" ]] && { echo "$out"; return 0; }
        fi
      fi
    fi
  fi

  # <basis>-<zahl>.<suffix>
  if [[ "$q" =~ ^(.+)-([0-9]+)\.(.+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local want="${BASH_REMATCH[2]}"
    local suffix="${BASH_REMATCH[3]}"
    local re="^$(escape_ere "$base")-[0-9]+\.${suffix}$"

    local out
    out="$(grep -E "$re" "$NAMES_FILE" | awk -v b="$base" -v w="$want" -v s="$suffix" '
      function v(n){sub("^"b"-","",n);sub("\\."s"$","",n);return n+0}
      {x=v($0); if(x>m){m=x;o=$0}}
      END{if(m>w)print o}
    ')"
    [[ -n "$out" ]] && { echo "$out"; return 0; }
  fi

  # <basis><zahl>.<suffix>
  if [[ "$q" =~ ^(.*[^0-9])([0-9]+)\.(.+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local want="${BASH_REMATCH[2]}"
    local suffix="${BASH_REMATCH[3]}"
    local re="^$(escape_ere "$base")[0-9]+\.${suffix}$"

    local out
    out="$(grep -E "$re" "$NAMES_FILE" | awk -v b="$base" -v w="$want" -v s="$suffix" '
      function v(n){sub("^"b,"",n);sub("\\."s"$","",n);return n+0}
      {x=v($0); if(x>m){m=x;o=$0}}
      END{if(m>w)print o}
    ')"
    [[ -n "$out" ]] && { echo "$out"; return 0; }
  fi

  # <basis><zahl>
  if [[ "$q" =~ ^(.*[^0-9])([0-9]+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local want="${BASH_REMATCH[2]}"
    local re="^$(escape_ere "$base")[0-9]+$"

    local out
    out="$(grep -E "$re" "$NAMES_FILE" | awk -v b="$base" -v w="$want" '
      function v(n){sub("^"b,"",n);return n+0}
      {x=v($0); if(x>m){m=x;o=$0}}
      END{if(m>w)print o}
    ')"
    [[ -n "$out" ]] && { echo "$out"; return 0; }
  fi

  [[ "$exact_exists" -eq 1 ]] && { echo "$q"; return 0; }
  return 1
}

###############################################################################
# apt search Fallback: Paketname aus apt-Ausgabe extrahieren
###############################################################################
apt_find_name() {
  local query="$1"
  command -v apt >/dev/null 2>&1 || return 1

  # apt search kann "Sorting... Full Text Search..." ausgeben; wir ignorieren alles,
  # was nicht mit "name/" beginnt.
  local lines names
  lines="$(apt search "$query" 2>/dev/null || true)"

  # Extrahiere Kandidaten (Paketname vor dem ersten '/')
  # Beispielzeile: "php8.4-bz2/trixie 8.4.11-1 ..."
  names="$(printf '%s\n' "$lines" | awk -F/ '/^[A-Za-z0-9][A-Za-z0-9+.-]*\//{print $1}' | sort -u)"

  [[ -z "$names" ]] && return 1

  # Bevorzugung:
  # 1) exakter Name (falls vorhanden)
  if printf '%s\n' "$names" | grep -Fxq "$query"; then
    printf '%s\n' "$query"
    return 0
  fi

  # 2) Wenn query ein "versioned name" ist, dann wähle die beste höhere Variante unter den Kandidaten.
  #    Wir nutzen dafür best_match_for auf Basis der Kandidaten: bauen temporär eine Kandidatenliste
  #    und wählen daraus den "besten" nach unseren Regeln, aber ohne Web-Liste zu verändern.
  local base="$query"

  # Kandidaten-Scoring durch unsere vorhandene Logik: wir nehmen den "maximalen" Treffer aus den Kandidaten,
  # der query als Muster entspricht (höchste Version).
  # Implementiert über mehrere Muster-Heuristiken (simple & robust).

  # a) <basis>-<zahl>-<suffix>
  if [[ "$base" =~ ^(.+)-([0-9]+)-(.+)$ ]]; then
    local b="${BASH_REMATCH[1]}" w="${BASH_REMATCH[2]}" s="${BASH_REMATCH[3]}"
    local out
    out="$(printf '%s\n' "$names" | awk -v b="$b" -v w="$w" -v s="$s" '
      $0 ~ ("^"b"-[0-9]+-"s"$") {
        tmp=$0; sub("^"b"-","",tmp); sub("-"s"$","",tmp); v=tmp+0
        if(v>w && v>best){best=v; bestn=$0}
      }
      END{if(bestn!="") print bestn}
    ')"
    [[ -n "$out" ]] && { printf '%s\n' "$out"; return 0; }
  fi

  # b) <prefix><dotted>-<suffix> (php8.2-bz2)
  if [[ "$base" == *-* ]]; then
    local prefix="${base%-*}" sfx="${base##*-}"
    if [[ "$prefix" =~ ^(.+?)([0-9]+(\.[0-9]+)+)$ ]]; then
      local b="${BASH_REMATCH[1]}"
      local out
      out="$(printf '%s\n' "$names" | awk -v b="$b" -v s="$sfx" '
        function score(ver,    i,n,a,sc){
          n=split(ver,a,"\\.")
          sc=0
          for(i=1;i<=n;i++){ sc=sc*1000 + (a[i]+0) }
          return sc
        }
        $0 ~ ("^"b"[0-9]+(\\.[0-9]+)+-"s"$") {
          tmp=$0; sub("^"b,"",tmp); sub("-"s"$","",tmp)
          v=score(tmp)
          if(v>best){best=v; bestn=$0}
        }
        END{if(bestn!="") print bestn}
      ')"
      [[ -n "$out" ]] && { printf '%s\n' "$out"; return 0; }
    fi
  fi

  # c) Fallback: erster Kandidat
  printf '%s\n' "$(printf '%s\n' "$names" | head -n1)"
  return 0
}

###############################################################################
# MAIN: dpkg -l FORMAT
###############################################################################
usage() {
  cat >&2 <<'EOF'
Usage:
  map-packages.sh <packages.txt>

Liest eine dpkg -l Datei und schreibt <packages.txt>_neu
EOF
}

main() {
  [[ $# -eq 1 ]] || { usage; exit 2; }
  local in_file="$1"
  [[ -f "$in_file" ]] || die "Datei nicht gefunden: $in_file"

  ensure_index

  local out_file="${in_file}_neu"
  local tmp_out="${out_file}.tmp"
  : > "$tmp_out"

  # NOTFOUND soll am Ende ggf. durch apt search reduziert werden
  declare -A NOTFOUND=()

  # Wir brauchen die Originaldaten der fehlenden Zeilen, um sie später (bei apt Treffer) wieder
  # an derselben Stelle einzufügen.
  declare -A MISS_STATUS=()
  declare -A MISS_VER=()
  declare -A MISS_ARCH=()
  declare -A MISS_REST=()
  declare -A MISS_ARCHSUF=()
  declare -A MISS_NAME=()
  declare -A MISS_MAPPED=()

  local miss_id=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Header / Trenner unverändert übernehmen
    if [[ ! "$line" =~ ^[a-z][a-z][[:space:]] ]]; then
      printf '%s\n' "$line" >> "$tmp_out"
      continue
    fi

    read -r status pkg ver arch rest <<<"$line"

    local name archsuffix
    if [[ "$pkg" == *:* ]]; then
      name="${pkg%%:*}"
      archsuffix=":${pkg##*:}"
    else
      name="$pkg"
      archsuffix=""
    fi

    local mapped
    if mapped="$(best_match_for "$name")"; then
      pkg="${mapped}${archsuffix}"
      printf '%s %-30s %-20s %-10s %s\n' \
        "$status" "$pkg" "$ver" "$arch" "$rest" >> "$tmp_out"
    else
      # zunächst nicht gefunden: Zeile noch NICHT final schreiben, sondern Marker + Daten merken
      miss_id=$((miss_id + 1))
      MISS_STATUS["$miss_id"]="$status"
      MISS_VER["$miss_id"]="$ver"
      MISS_ARCH["$miss_id"]="$arch"
      MISS_REST["$miss_id"]="$rest"
      MISS_ARCHSUF["$miss_id"]="$archsuffix"
      MISS_NAME["$miss_id"]="$name"
      NOTFOUND["$name"]=1

      printf '__PKGMAP_MISSING__%s__\n' "$miss_id" >> "$tmp_out"
    fi
  done < "$in_file"

  # Zweite Chance: apt search für alle NOTFOUND
  if (( ${#NOTFOUND[@]} > 0 )); then
    if command -v apt >/dev/null 2>&1; then
      # Für jeden missing-id: apt search auf den Namen, ggf. Mapping setzen
      for id in "${!MISS_NAME[@]}"; do
        local n="${MISS_NAME[$id]}"
        local a
        if a="$(apt_find_name "$n")"; then
          # Wenn apt etwas findet, verwenden wir den gefundenen Namen
          MISS_MAPPED["$id"]="$a"
          unset 'NOTFOUND[$n]'
        fi
      done
    fi
  fi

  # Finalen Output schreiben: Marker ersetzen (wenn apt gemappt), sonst Markerzeilen weglassen
  : > "$out_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^__PKGMAP_MISSING__([0-9]+)__$ ]]; then
      local id="${BASH_REMATCH[1]}"
      if [[ -n "${MISS_MAPPED[$id]+x}" ]]; then
        local status="${MISS_STATUS[$id]}"
        local ver="${MISS_VER[$id]}"
        local arch="${MISS_ARCH[$id]}"
        local rest="${MISS_REST[$id]}"
        local archsuffix="${MISS_ARCHSUF[$id]}"
        local pkg="${MISS_MAPPED[$id]}${archsuffix}"

        printf '%s %-30s %-20s %-10s %s\n' \
          "$status" "$pkg" "$ver" "$arch" "$rest" >> "$out_file"
      fi
      # Wenn kein apt-Mapping: Marker wird nicht geschrieben -> Zeile endgültig entfernt
      continue
    fi

    printf '%s\n' "$line" >> "$out_file"
  done < "$tmp_out"

  rm -f "$tmp_out"

  # Übrig gebliebene NOTFOUND auf Konsole
  if (( ${#NOTFOUND[@]} > 0 )); then
    echo "Nicht gefundene Pakete:"
    for p in "${!NOTFOUND[@]}"; do
      echo "  $p"
    done | sort
  fi
}

main "$@"
