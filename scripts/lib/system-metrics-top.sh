#!/usr/bin/env bash
# Top CPU/memory process list caches for system-metrics-collector.
# Expected caller context: cache_dir; sets cpu_top and mem_top.
# shellcheck disable=SC2154 # cache_dir provided by system-metrics-collector.sh

refresh_process_tops() {
  # Retrieve top CPU processes. We cache this query for 24s to avoid expensive 'ps' calls on every poll.
  # The write is done atomically to prevent other modules from reading incomplete JSON configurations.
  cpu_top_file="$cache_dir/cpu-top.json"
  if [ "$(cache_file_age "$cpu_top_file")" -ge 24 ] 2>/dev/null || [ ! -f "$cpu_top_file" ]; then
    cpu_top=$(ps -eo pcpu,comm --sort=-pcpu 2>/dev/null | awk '
      NR>1 && NR<=4 {
        pcpu=$1; $1=""
        sub(/^ +/, "")
        gsub(/"/, "\\\"", $0)
        items = items (items ? "," : "") "\"" $0 " (" pcpu "%)\""
      }
      END {
        print "[" items "]"
      }
    ')
    [ -z "$cpu_top" ] || [ "$cpu_top" = "null" ] && cpu_top="[]"
    tmp_cpu_top="$cpu_top_file.tmp.$$"
    printf '%s\n' "$cpu_top" >"$tmp_cpu_top"
    mv -f "$tmp_cpu_top" "$cpu_top_file"
  else
    cpu_top=$(cat "$cpu_top_file" 2>/dev/null || echo "[]")
  fi

  # Retrieve top memory consuming processes. Cached for 24s and written atomically.
  mem_top_file="$cache_dir/mem-top.json"
  if [ "$(cache_file_age "$mem_top_file")" -ge 24 ] 2>/dev/null || [ ! -f "$mem_top_file" ]; then
    mem_top=$(ps -eo pmem,rss,comm --sort=-rss 2>/dev/null | awk '
      NR>1 && NR<=4 {
        pmem=$1; rss=$2; $1=""; $2=""
        sub(/^ +/, "")
        gsub(/"/, "\\\"", $0)
        if (rss > 1048576) {
          size=sprintf("%.1f GiB", rss/1048576)
        } else {
          size=sprintf("%d MiB", rss/1024)
        }
        items = items (items ? "," : "") "\"" $0 " (" size ")\""
      }
      END {
        print "[" items "]"
      }
    ')
    [ -z "$mem_top" ] || [ "$mem_top" = "null" ] && mem_top="[]"
    tmp_mem_top="$mem_top_file.tmp.$$"
    printf '%s\n' "$mem_top" >"$tmp_mem_top"
    mv -f "$tmp_mem_top" "$mem_top_file"
  else
    mem_top=$(cat "$mem_top_file" 2>/dev/null || echo "[]")
  fi
}
