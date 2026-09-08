#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# @Desc Validate Linux ACPI support for the Intel MRRM and ERDT tables.

cd "$(dirname "$0")" 2>/dev/null || exit 1
# shellcheck source=/dev/null
source ../.env

SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
ACPI_TABLE_DIR="$SYSFS_ROOT/firmware/acpi/tables"
MEMORY_RANGE_DIR="$SYSFS_ROOT/firmware/acpi/memory_ranges"
TEST_CASE=""

usage() {
  cat <<'EOF'
Usage: rdt_acpi_table_test.sh -t check_mrrm_erdt

Cases:
  check_mrrm_erdt  Validate kernel retrieval and parsing of MRRM and ERDT
EOF
}

read_u8() {
  od -An -v -tu1 -j "$2" -N 1 "$1" | tr -d '[:space:]'
}

read_le16() {
  local byte0 byte1
  read -r byte0 byte1 < <(od -An -v -tu1 -j "$2" -N 2 "$1")
  printf '%u\n' "$((byte0 | (byte1 << 8)))"
}

read_le32() {
  local byte0 byte1 byte2 byte3
  read -r byte0 byte1 byte2 byte3 < <(od -An -v -tu1 -j "$2" -N 4 "$1")
  printf '%u\n' "$((byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)))"
}

validate_acpi_table() {
  local signature="$1"
  local table="$ACPI_TABLE_DIR/$signature"
  local actual_signature declared_length actual_length revision checksum

  [[ -r "$table" ]] || block_test "Linux did not expose the ACPI $signature table"

  actual_signature="$(od -An -v -tc -N 4 "$table" | tr -d '[:space:]')"
  [[ "$actual_signature" == "$signature" ]] ||
    die "$table has signature '$actual_signature', expected '$signature'"

  declared_length="$(read_le32 "$table" 4)"
  actual_length="$(stat -c %s "$table")" || die "Cannot stat $table"
  ((declared_length >= 36)) || die "$signature table is shorter than the ACPI header"
  [[ "$actual_length" == "$declared_length" ]] ||
    die "$signature length mismatch: header=$declared_length sysfs=$actual_length"

  if ! od -An -v -tu1 "$table" |
    awk '{ for (i = 1; i <= NF; i++) sum += $i } END { exit (sum % 256 != 0) }'; then
    die "$signature table checksum is invalid"
  fi

  revision="$(read_u8 "$table" 8)"
  checksum="$(read_u8 "$table" 9)"
  [[ "$revision" == 1 ]] || die "Unsupported $signature table revision $revision"
  test_print_trc "$signature retrieved through Linux ACPI: length=$actual_length revision=$revision checksum=$checksum"
}

validate_subtables() {
  local signature="$1"
  local offset="$2"
  local max_type="$3"
  local table="$ACPI_TABLE_DIR/$signature"
  local table_length type length count=0

  table_length="$(read_le32 "$table" 4)"
  ((table_length >= offset)) || die "$signature table is shorter than its fixed header"

  while ((offset < table_length)); do
    ((table_length - offset >= 4)) ||
      die "$signature has a truncated subtable header at offset $offset"
    type="$(read_le16 "$table" "$offset")"
    length="$(read_le16 "$table" "$((offset + 2))")"
    ((type <= max_type)) || die "$signature has unknown subtable type $type"
    ((length >= 4)) || die "$signature subtable type $type has invalid length $length"
    ((offset + length <= table_length)) ||
      die "$signature subtable type $type extends past the table boundary"
    test_print_trc "$signature subtable: offset=$offset type=$type length=$length"
    offset=$((offset + length))
    count=$((count + 1))
  done

  ((count > 0)) || die "$signature contains no subtables"
}

validate_mrrm_sysfs() {
  local range attr value count=0
  local max_regions

  [[ -d "$MEMORY_RANGE_DIR" ]] ||
    die "Linux MRRM parser did not create $MEMORY_RANGE_DIR"
  max_regions="$(read_u8 "$ACPI_TABLE_DIR/MRRM" 36)"
  ((max_regions > 0)) || die "MRRM reports zero supported memory regions"

  for range in "$MEMORY_RANGE_DIR"/range[0-9]*; do
    [[ -d "$range" ]] || continue
    for attr in base length node local_region_id remote_region_id; do
      [[ -r "$range/$attr" ]] || die "Linux MRRM parser omitted $range/$attr"
    done

    value="$(<"$range/length")"
    if [[ ! "$value" =~ ^0x[0-9a-fA-F]+$ ]] || ((value == 0)); then
      die "Invalid MRRM memory range length '$value' in $range"
    fi
    for attr in node local_region_id remote_region_id; do
      value="$(<"$range/$attr")"
      [[ "$value" =~ ^-?[0-9]+$ ]] || die "Invalid MRRM $attr '$value' in $range"
    done

    test_print_trc "MRRM $(basename "$range"): base=$(<"$range/base") length=$(<"$range/length") node=$(<"$range/node") local=$(<"$range/local_region_id") remote=$(<"$range/remote_region_id")"
    count=$((count + 1))
  done

  ((count > 0)) || die "Linux MRRM parser exposed no memory ranges"
  test_print_trc "Linux MRRM parser exposed $count ranges and max_regions=$max_regions"
}

check_kernel_messages() {
  local messages failures

  if ! messages="$(dmesg 2>/dev/null)"; then
    test_print_wrg "Cannot read kernel log; MRRM/ERDT error scan skipped"
    return
  fi

  failures="$(grep -Ei 'MRRM|ERDT' <<<"$messages" |
    grep -Ei 'FW_BUG|error|fail|invalid|unsupported|truncated|malformed|mismatch' || true)"
  [[ -z "$failures" ]] || die "MRRM/ERDT kernel initialization errors detected: $failures"
}

check_mrrm_erdt() {
  local acpica_version max_closid

  validate_acpi_table MRRM
  validate_subtables MRRM 64 0
  validate_mrrm_sysfs

  validate_acpi_table ERDT
  validate_subtables ERDT 64 10
  max_closid="$(read_le32 "$ACPI_TABLE_DIR/ERDT" 36)"
  test_print_trc "ERDT maximum supported CLOSID: $max_closid"

  check_kernel_messages
  if [[ -r "$SYSFS_ROOT/module/acpi/parameters/acpica_version" ]]; then
    acpica_version="$(<"$SYSFS_ROOT/module/acpi/parameters/acpica_version")"
    test_print_trc "Linux ACPICA version: $acpica_version"
  fi
  test_print_trc "Linux ACPI MRRM/ERDT support: PASS"
}

while getopts ":t:h" option; do
  case "$option" in
    t) TEST_CASE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) test_print_err "Option -$OPTARG requires an argument"; usage; exit 1 ;;
    \?) test_print_err "Invalid option: -$OPTARG"; usage; exit 1 ;;
  esac
done

case "$TEST_CASE" in
  check_mrrm_erdt) check_mrrm_erdt ;;
  *) test_print_err "Unsupported testcase: $TEST_CASE"; usage; exit 1 ;;
esac