# Shared when-evaluator for ctx__match_* and ospkg manifests.
# Invoke with: jq -L <lib-dir> --argjson ctx '{...}' --argjson when '{...}' -f ctx-when-eval.jq

def ic: ascii_downcase;

def ctx_val($k): ($ctx[$k] // "") | tostring;

def id_like_tokens($s):
  ($s | tostring | gsub("\\s+"; " ") | gsub("^\\s+"; "") | gsub("\\s+$"; "")) as $t
  | if $t == "" then [] else [$t | split(" ")[] | select(length > 0) | ic] end;

def id_like_has($tok; $actual):
  id_like_tokens($actual) | index($tok | ic) != null;

def semver_norm($s): $s | tostring | ltrimstr("v") | ltrimstr("V");

def semver_parse($s):
  semver_norm($s) as $n
  | ($n | split("+")[0]) as $core_pre
  | ($core_pre | split("-")[0]) as $core
  | ($core_pre | if index("-") then ($core_pre | split("-")[1:] | join("-")) else "" end) as $pre
  | {core: $core, pre: $pre};

def semver_core_parts($core): [$core | split(".")[] | try tonumber catch null];

def semver_cmp_core($a; $b):
  (semver_core_parts($a.core) | length) as $la
  | (semver_core_parts($b.core) | length) as $lb
  | ([$la, $lb] | max) as $max
  | reduce range(0; $max) as $i (0;
      if . != 0 then .
      elif (semver_core_parts($a.core)[$i] // 0) > (semver_core_parts($b.core)[$i] // 0) then 1
      elif (semver_core_parts($a.core)[$i] // 0) < (semver_core_parts($b.core)[$i] // 0) then -1
      else 0
      end
    );

def semver_cmp_pre($a; $b):
  if $a.pre == "" and $b.pre == "" then 0
  elif $a.pre == "" then 1
  elif $b.pre == "" then -1
  elif $a.pre == $b.pre then 0
  elif ($a.pre | ic) < ($b.pre | ic) then -1
  else 1
  end;

def ver_cmp_jq($a; $b):
  (semver_parse($a)) as $pa | (semver_parse($b)) as $pb
  | if ($pa.core | test("^[0-9]+(\\.[0-9]+)*$") | not) or ($pb.core | test("^[0-9]+(\\.[0-9]+)*$") | not)
    then null
  else
    (semver_cmp_core($pa; $pb)) as $c
    | if $c != 0 then $c else semver_cmp_pre($pa; $pb) end
  end;

def compare_eq($key; $expected; $actual):
  if $key == "os.id_like" then
    if ($expected | type) == "array" then
      any($expected[]; id_like_has(.; $actual))
    else
      id_like_has($expected; $actual)
    end
  else
    if ($expected | type) == "array" then
      any($expected[]; ($actual | ic) == (. | ic))
    else
      ($actual | ic) == ($expected | ic)
    end
  end;

def compare_ne($key; $expected; $actual):
  if $key == "os.id_like" then
    if ($expected | type) == "array" then
      all($expected[]; (id_like_has(.; $actual) | not))
    else
      (id_like_has($expected; $actual) | not)
    end
  else
    if ($expected | type) == "array" then
      all($expected[]; ($actual | ic) != (. | ic))
    else
      ($actual | ic) != ($expected | ic)
    end
  end;

def compare_order($key; $op; $actual; $expected):
  if $key == "os.id_like" then false
  else
    (ver_cmp_jq($actual; $expected)) as $c
    | if $c == null then false
      elif $op == "lt" then $c < 0
      elif $op == "lte" then $c <= 0
      elif $op == "gt" then $c > 0
      elif $op == "gte" then $c >= 0
      else false
      end
  end;

def compare_op($key; $op; $expected; $actual):
  if $op == "eq" then compare_eq($key; $expected; $actual)
  elif $op == "ne" then compare_ne($key; $expected; $actual)
  elif ($op | IN("lt", "lte", "gt", "gte")) then compare_order($key; $op; $actual; $expected)
  else false
  end;

def eval_op_entry($key; $op; $val):
  compare_op($key; $op; $val; ctx_val($key));

def eval_value($key; $value):
  if ($value | type) == "object" then
    all($value | to_entries[]; eval_op_entry($key; .key; .value))
  elif ($value | type) == "array" then
    compare_eq($key; $value; ctx_val($key))
  else
    compare_eq($key; $value; ctx_val($key))
  end;

def cond_atom($key; $value): eval_value($key; $value);

def cond_matches:
  . | to_entries | all(.key as $k | .value as $v | cond_atom($k; $v));

def when_matches:
  if . == null then true
  elif type == "array" then [.[] | cond_matches] | any
  elif type == "object" then cond_matches
  else false
  end;

def item_when_matches:
  if has("when") | not then true
  elif .when == null then true
  elif (.when | type) == "array" then [.when[] | cond_matches] | any
  elif (.when | type) == "object" then .when | cond_matches
  else false
  end;
