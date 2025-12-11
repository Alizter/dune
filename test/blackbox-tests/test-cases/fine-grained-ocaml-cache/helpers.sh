# Common setup for fine-grained cache tests

# CR-soon Alizter: This shouldn't be needed eventually
# Set up isolated cache directory
export XDG_CACHE_HOME=$PWD/.xdg-cache
mkdir -p $XDG_CACHE_HOME/dune/db/files/v5
mkdir -p $XDG_CACHE_HOME/dune/db/meta/v5
mkdir -p $XDG_CACHE_HOME/dune/db/temp
mkdir -p $XDG_CACHE_HOME/dune/db/values/v5

# CR-soon Alizter: We shouldn't do this here
# Create minimal dune-project
cat > dune-project << EOF
(lang dune 3.21)
EOF

# Show which modules were compiled (both byte and native)
show_compiled() {
  grep -oE 'ocaml(c|opt)[^ ]* .* -c -impl [^ ]+' _build/log | sed 's/.*-impl /  /' | sed 's/)$//' | sort -u || true
}

# Count how many module compilations occurred
count_compiled() {
  grep -oE 'ocaml(c|opt)[^ ]* .* -c -impl [^ ]+' _build/log | wc -l
}

# Show which modules were compiled (bytecode only)
show_compiled_byte() {
  grep -oE 'ocamlc[^ ]* .* -c -impl [^ ]+' _build/log | sed 's/.*-impl /  /' | sed 's/)$//' | sort -u || true
}

# Count bytecode compilations only
count_compiled_byte() {
  grep -oE 'ocamlc[^ ]* .* -c -impl [^ ]+' _build/log | wc -l
}

# Show fine-grained cache hit messages
show_cache_hits() {
  grep "fine-cache HIT" _build/log | sed 's/.*# /# /' | sort -u || true
}

# Show fine-grained cache miss messages
show_cache_misses() {
  grep "fine-cache MISS" _build/log | sed 's/.*# /# /' | sort -u || true
}

# Show audit/verification results
show_audit() {
  grep -E "fine-cache (VERIFY|VERIFIED|MISMATCH)" _build/log | sed 's/.*# /# /' | sort -u || true
}

# Create an unwrapped library with n modules.
# Usage: create_unwrapped_library <name> <num_modules> [dep_lib]
# Each module exports a value and optionally depends on the corresponding
# module in a previous library.
create_unwrapped_library() {
  local name=$1
  local num_modules=$2
  local dep_lib=$3
  mkdir -p $name
  if [ -n "$dep_lib" ]; then
    cat > $name/dune << EOF
(library
 (name $name)
 (wrapped false)
 (libraries $dep_lib))
EOF
  else
    cat > $name/dune << EOF
(library
 (name $name)
 (wrapped false))
EOF
  fi
  for i in $(seq 1 $num_modules); do
    local mod_name="${name}_mod_$i"
    cat > $name/$mod_name.mli << EOF
val value : int
EOF
    if [ -n "$dep_lib" ]; then
      local dep_mod="${dep_lib}_mod_$i"
      local dep_mod_cap=$(echo "$dep_mod" | sed 's/\(.\)/\U\1/')
      cat > $name/$mod_name.ml << EOF
let value = ${dep_mod_cap}.value + 1
EOF
    else
      cat > $name/$mod_name.ml << EOF
let value = $i
EOF
    fi
  done
}

# Create a wrapped library with n modules.
# Usage: create_wrapped_library <name> <num_modules> [dep_lib]
# Module names are simple (mod_1, mod_2) and accessed via Libname.Mod_1.
create_wrapped_library() {
  local name=$1
  local num_modules=$2
  local dep_lib=$3
  mkdir -p $name
  if [ -n "$dep_lib" ]; then
    cat > $name/dune << EOF
(library
 (name $name)
 (libraries $dep_lib))
EOF
  else
    cat > $name/dune << EOF
(library
 (name $name))
EOF
  fi
  for i in $(seq 1 $num_modules); do
    local mod_name="mod_$i"
    cat > $name/$mod_name.mli << EOF
val value : int
EOF
    if [ -n "$dep_lib" ]; then
      # Capitalize library name for module access
      local dep_lib_cap=$(echo "$dep_lib" | sed 's/\(.\)/\U\1/')
      cat > $name/$mod_name.ml << EOF
let value = ${dep_lib_cap}.Mod_$i.value + 1
EOF
    else
      cat > $name/$mod_name.ml << EOF
let value = $i
EOF
    fi
  done
}
