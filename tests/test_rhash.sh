#!/bin/sh
# Run RHash tests
# Usage: test_rhash.sh [ --full | --shared ] <PATH-TO-EXECUTABLE>
export LC_ALL=C

# read options
while [ "$#" -gt 0 ]; do
  case $1 in
    --full)
      OPT_FULL=1
      ;;
    --shared)
      OPT_SHARED=1
      ;;
    *)
      test -z "$rhash" && rhash="$1"
      ;;
  esac
  shift
done
_sdir="$(dirname "$0")"
SCRIPT_DIR="$(cd "$_sdir" && pwd)"
UPPER_DIR="$(cd "$_sdir/.." && pwd)"

# find the path of rhash binary
if test -x "$rhash"; then
  rhash="$(cd $(dirname $rhash) && echo $PWD/${rhash##*/})"
elif test -z "$rhash"; then
  command -v rhash 2>/dev/null >/dev/null && _path="$(command -v rhash 2>/dev/null)"
  if test -x "$_path"; then
    rhash="$_path"
  elif test -x /usr/bin/rhash; then
    rhash=/usr/bin/rhash
  elif test -x /usr/local/bin/rhash; then
    rhash=/usr/local/bin/rhash
  fi
fi
if [ ! -f "$rhash" ]; then
  echo "Fatal: file $rhash not found"
  exit 1
elif [ ! -x "$rhash" ]; then
  echo "Fatal: $rhash is not an executable file"
  exit 1
fi

win32()
{
  case "$(uname -s)" in
    MINGW*|MSYS*|[cC][yY][gG][wW][iI][nN]*) return 0 ;;
  esac
  return 1
}

mingw_or_ucrt()
{
  case "$MSYSTEM" in
    MINGW32|MINGW64|UCRT32|UCRT64) return 0 ;;
  esac
  return 1
}

# detect shared library
if [ -n "$OPT_SHARED" -a -d "$UPPER_DIR/librhash" ]; then
  D="$UPPER_DIR/librhash"
  N="$D/librhash"
  if [ -r $N.1.dylib ] && ( uname -s | grep -qi "^darwin" || [ ! -r $N.so.1 ] ); then
    export DYLD_LIBRARY_PATH="$D:$DYLD_LIBRARY_PATH"
  elif ls $D/*rhash.dll 2>/dev/null >/dev/null && ( win32 || [ ! -r $N.so.1 ] ); then
    export PATH="$D:$PATH"
  elif [ -r $N.so.1 ]; then
    export LD_LIBRARY_PATH="$D:$LD_LIBRARY_PATH"
  else
    echo "shared library not found at $D"
  fi
fi

# run smoke test: test exit code of a simple command
$rhash --printf "" -m ""
res=$?
if [ $res -ne 0 ]; then
  if [ $res -eq 127 ]; then
    echo "error: could not load dynamic libraries or execute $rhash"
    [ -z "$OPT_SHARED" ] && echo "try running with --shared option"
  elif [ $res -eq 139 ]; then
    echo "error: got segmentation fault by running $rhash"
  else
    echo "error: obtained unexpected exit_code = $res from $rhash"
  fi
  exit 2
fi

# create temp directory
for _tmp in "$TMPDIR" "$TEMPDIR" "/tmp" ; do
  [ -d "$_tmp" ] && break
done
RANDNUM=$RANDOM
test -z "$RANDNUM" && jot -r 1 2>/dev/null >dev/null && RANDNUM=$(jot -r 1 1 32767) || RANDNUM=0
RHASH_TMP="$_tmp/rhash-test-$RANDNUM-$$"
remove_tmpdir()
{
  cd "$SCRIPT_DIR"
  rm -rf "$RHASH_TMP";
}
trap remove_tmpdir EXIT

# prepare test files
mkdir $RHASH_TMP || die "Unable to create tmp dir."
cp "$SCRIPT_DIR/test1K.data" $RHASH_TMP/test1K.data
cd "$RHASH_TMP"

# get the list of supported hash options
HASHOPT="`$rhash --list-hashes|sed 's/ .*$//;/[^23]-/s/-\([0-9R]\)/\1/'|tr A-Z a-z`"

fail_cnt=0
test_num=1
sub_test=0
new_test() {
  printf "%2u. %s" $test_num "$1"
  test_num=$((test_num+1))
  sub_test=0
}

print_failed() {
    st=$( test "$1" = "." -o "$sub_test" -gt 1 && printf " Subtest #$sub_test" )
    printf "Failed$st\n"
}

# verify obtained value $1 against the expected value $2
check() {
  sub_test=$((sub_test+1))
  if [ "$1" = "$2" ]; then
    test "$3" = "." || printf "Ok\n"
  else
    print_failed "$3"
    printf "obtained: \"%s\"\n" "$1"
    printf "expected: \"%s\"\n" "$2"
    fail_cnt=$((fail_cnt+1))
    return 1;
  fi
  return 0
}

# match obtained value $1 against given grep-regexp $2
match_line() {
  if printf "$1" | grep -vq "$2"; then
    printf "obtained: \"%s\"\n" "$1"
    printf "regexp:  /%s/\n" "$2"
    fail_cnt=$((fail_cnt+1))
    return 1
  fi
  return 0
}

# match obtained value $1 against given grep-regexp $2
match() {
  sub_test=$((sub_test+1))
  if echo "$1" | grep -vq "$2"; then
    print_failed "$3"
    printf "obtained: \"%s\"\n" "$1"
    printf "regexp:  /%s/\n" "$2"
    fail_cnt=$((fail_cnt+1))
    return 1;
  else
    test "$3" = "." || printf "Ok\n"
  fi
  return 0
}

new_test "test with a text string:    "
TEST_RESULT=$( $rhash --message "abc" | tail -n1 )
TEST_EXPECTED="(message) 352441C2"
check "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test stdin processing:      "
TEST_STR="test_string1"
TEST_RESULT=$( printf "abc" | $rhash -CHMETAGW --sfv - | tail -n1 )
TEST_EXPECTED="(stdin) 352441C2 900150983CD24FB0D6963F7D28E17F72 A9993E364706816ABA3E25717850C26C9CD0D89D ASD4UJSEH5M47PDYB46KBTSQTSGDKLBHYXOMUIA A448017AAF21D8525FC10AE87AA6729D VGMT4NSHA2AWVOR6EVYXQUGCNSONBWE5 4E2448A4C6F486BB16B6562C73B4020BF3043E3A731BCE721AE1B303D97E6D4C7181EEBDB6C57E277D0E34957114CBD6C797FC9D95D8B582D225292076D4EEF5 4E2919CF137ED41EC4FB6270C61826CC4FFFB660341E0AF3688CD0626D23B481"
check "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test with 1Kb data file:    "
TEST_RESULT=$( $rhash --printf "%f %d %C %M %H %E %G %T %A %W\n" test1K.data 2>/dev/null )
TEST_EXPECTED="test1K.data . B70B4C26 B2EA9F7FCEA831A4A63B213F41A8855B 5B00669C480D5CFFBDFA8BDBA99561160F2D1B77 5AE257C47E9BE1243EE32AABE408FB6B 7A6682133082A49C37DB7B008394AEB9C184D5FB2A8D2A6251DD4BBA5F6744B4 4OQY25UN2XHIDQPV5U6BXAZ47INUCYGIBK7LFNI LMAGNHCIBVOP7PP2RPN2TFLBCYHS2G3X D606B7F44BD288759F8869D880D9D4A2F159D739005E72D00F93B814E8C04E657F40C838E4D6F9030A8C9E0308A4E3B450246250243B2F09E09FA5A24761E26B"
check "$TEST_RESULT" "$TEST_EXPECTED" .
# test calculation/verification of reversed GOST hashes with 1Kb data file
TEST_RESULT=$( $rhash --simple --gost --gost-cryptopro --gost-reverse test1K.data )
TEST_EXPECTED="test1K.data bb4c042bacee51bbabc186107e6020b20991fd4ea119672da24dbe5deeb30b89 06cc52d9a7fb5137d01667d1641683620060391722a56222bb4b14ab332ec9d9"
check "$TEST_RESULT" "$TEST_EXPECTED" .
TEST_RESULT=$( $rhash --simple --gost --gost-cryptopro --gost-reverse test1K.data | $rhash -vc - 2>/dev/null | grep test1K.data )
match "$TEST_RESULT" "^test1K.data *OK"

new_test "test symlinked file size:   "
MSYS=winsymlinks:nativestrict CYGWIN=winsymlinks:nativestrict ln -s test1K.data test1K-symlink.data >/dev/null 2>&1
if [ -L "test1K-symlink.data" ]; then
  TEST_RESULT=$( $rhash --printf "%f %d %s\n" test1K-symlink.data 2>/dev/null )
  TEST_EXPECTED="test1K-symlink.data . 1024"
  check "$TEST_RESULT" "$TEST_EXPECTED"
else
  printf "Skipped - unable to create the symlink\n"
fi

new_test "test handling empty files:  "
EMPTY_FILE="$RHASH_TMP/test-empty.file"
printf "" > "$EMPTY_FILE"
TEST_RESULT=$( $rhash -p "%m" "$EMPTY_FILE" )
check "$TEST_RESULT" "d41d8cd98f00b204e9800998ecf8427e" .
# test processing of empty message
TEST_RESULT=$( $rhash -p "%m" -m "" )
check "$TEST_RESULT" "d41d8cd98f00b204e9800998ecf8427e" .
# test processing of empty stdin
TEST_RESULT=$( printf "" | $rhash -p "%m" - )
check "$TEST_RESULT" "d41d8cd98f00b204e9800998ecf8427e" .
# test verification of empty file
TEST_RESULT=$( $rhash -c --brief "$EMPTY_FILE" | tr -d '\r' )
check "$TEST_RESULT" "Nothing to verify"

# Test the SFV format using test1K.data
new_test "test default format:        "
MATCH_LOG="$RHASH_TMP/match_err.log"
$rhash test1K.data | tr -d '\r' | (
  read l; match_line "$l" "^; Generated by RHash"
  read l; match_line "$l" "^; Written by"
  read l; match_line "$l" "^;\$"
  read l; match_line "$l" "^; *1024  [0-9:\.]\{8\} [0-9-]\{10\} test1K.data\$"
  read l; match_line "$l" "^test1K.data B70B4C26\$"
) > "$MATCH_LOG"
if [ ! -s "$MATCH_LOG" ]; then
  printf "Ok\n"
else
  printf "Failed\n"
  fail_cnt=$((fail_cnt+1))
  cat "$MATCH_LOG"
fi
rm -f "$MATCH_LOG"

new_test "test %x, %b, %B modifiers:  "
TEST_RESULT=$( $rhash -p '%f %s %xC %bc %bM %Bh %bE %bg %xT %xa %bW\n' -m "a" )
TEST_EXPECTED="(message) 1 E8B7BE43 5c334qy BTAXLOOA6G3KQMODTHRGS5ZGME hvfkN/qlp/zhXR3cuerq6jd2Z7g= XXSSZMY54M7EMJC6AX55XVX3EQ xiyqtg44zbhmfjtr5eytk4rxreqkobntmoyddiolj7ad4aoorxzq 16614B1F68C5C25EAF6136286C9C12932F4F73E87E90A273 86f7e437faa5a7fce15d1ddcb9eaeaea377667b8 RLFCMATZFLWG6ENGOIDFGH5X27YN75MUCMKF42LTYRIADUAIPNBNCG6GIVATV37WHJBDSGRZCRNFSGUSEAGVMAMV4U5UPBME7WXCGGQ"
check "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test %u modifier:           "
mkdir -p "dir1/d@" && printf "a" > "dir1/d@/=@+.txt"
TEST_RESULT=$( $rhash -p '%uf %Uf %ud %Ud %Up %uxc\n' "dir1/d@/=@+.txt" )
TEST_EXPECTED="%3d%40%2b.txt %3D%40%2B.txt dir1%2fd%40 dir1%2Fd%40 dir1%2Fd%40%2F%3D%40%2B.txt e8b7be43"
check "$TEST_RESULT" "$TEST_EXPECTED" .
TEST_RESULT=$( $rhash -p '%up %uxc %uxC %ubc %ubC\n' "dir1/d@/=@+.txt" )
TEST_EXPECTED="dir1%2fd%40%2f%3d%40%2b.txt e8b7be43 E8B7BE43 5c334qy 5C334QY"
check "$TEST_RESULT" "$TEST_EXPECTED" .
TEST_RESULT=$( $rhash -p '%uBc %UBc %Bc %u@c %U@c\n' -m "a" )
TEST_EXPECTED="6Le%2bQw%3d%3d 6Le%2BQw%3D%3D 6Le+Qw== %e8%b7%beC %E8%B7%BEC"
check "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test special characters:    "
if ! win32; then
  NAME_R="$(printf 'a/\r1')"
  NAME_N="$(printf 'a/\n2')"
  if mkdir a && touch "$NAME_R" "$NAME_N" 2>/dev/null && test -r "$NAME_R" && test -r "$NAME_N"; then
    TEST_RESULT=$( $rhash -p '\^%f ' "$NAME_R" "$NAME_N" )
    TEST_EXPECTED='\\r1 \\n2 '
    check "$TEST_RESULT" "$TEST_EXPECTED" .
    TEST_RESULT=$( $rhash -p '\^%p ' "$NAME_R" "$NAME_N" )
    TEST_EXPECTED='\a/\r1 \a/\n2 '
    check "$TEST_RESULT" "$TEST_EXPECTED" .
    TEST_RESULT=$( printf '\\00000000 a/\\r1\n' | $rhash -c --brief - 2>&1 | head -n1 | tr -d ' ' )
    TEST_EXPECTED='\a/\r1OK'
    check "$TEST_RESULT" "$TEST_EXPECTED" .
    TEST_RESULT=$( printf '\\00000000 a/\\n2\n' | $rhash -c --brief - 2>&1 | head -n1 | tr -d ' ' )
    TEST_EXPECTED='\a/\n2OK'
    check "$TEST_RESULT" "$TEST_EXPECTED" .
  fi
fi
TEST_RESULT=$( $rhash -p '\63\1\277\x0f\x1\t\\ \x34\r' -m "" )
TEST_EXPECTED=$( printf '\63\1\277\17\1\t\\ 4\r' )
check "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test file lists:            "
F="$RHASH_TMP/t"
touch ${F}1 ${F}2 ${F}3 ${F}4
printf "${F}2\n${F}3\n" > ${F}l
TEST_RESULT=$($rhash -p '%f ' ${F}1 --file-list ${F}l ${F}4)
check "$TEST_RESULT" "t1 t2 t3 t4 "
rm -f ${F}1 ${F}2 ${F}3 ${F}4 ${F}l

new_test "test eDonkey link:          "
TEST_RESULT=$( $rhash -p '%L %l\n' -m "a" )
TEST_EXPECTED="ed2k://|file|%28message%29|1|BDE52CB31DE33E46245E05FBDBD6FB24|h=Q336IN72UWT7ZYK5DXOLT2XK5I3XMZ5Y|/ ed2k://|file|%28message%29|1|bde52cb31de33e46245e05fbdbd6fb24|h=q336in72uwt7zyk5dxolt2xk5i3xmz5y|/"
check "$TEST_RESULT" "$TEST_EXPECTED" .
# test verification of ed2k links
TEST_RESULT=$( $rhash -L test1K.data | $rhash -vc - 2>/dev/null | grep test1K.data )
match "$TEST_RESULT" "^test1K.data *OK"

if [ -n "$OPT_FULL" ]; then
  new_test "test all hash options:      "
  errors=0
  for opt in $HASHOPT ; do
    TEST_RESULT=$( $rhash --$opt --simple -m "a" )
    match "$TEST_RESULT" "\b[0-9a-z]\{8,128\}\b" . || errors=$((errors+1))
  done
  check $errors 0
fi

new_test "test checking all hashes:   "
TEST_RESULT=$( $rhash --simple -a test1K.data | $rhash -vc - 2>/dev/null | grep test1K.data )
match "$TEST_RESULT" "^test1K.data *OK" .
# verify a filepath started by star ('*') character
TEST_RESULT=$( echo "b70b4c26 *test1K.data" | $rhash -Cc - 2>/dev/null | grep test1K.data )
match "$TEST_RESULT" "^test1K.data *OK"

new_test "test magnet links:          "
TEST_RESULT=$( $rhash --magnet --crc32c test1K.data )
TEST_EXPECTED="magnet:?xl=1024&dn=test1K.data&xt=urn:crc32c:2cdf6e8f"
check "$TEST_RESULT" "$TEST_EXPECTED" .
# test magnet default format
TEST_RESULT=$( $rhash --magnet test1K.data )
TEST_EXPECTED="magnet:?xl=1024&dn=test1K.data&xt=urn:tree:tiger:4oqy25un2xhidqpv5u6bxaz47inucygibk7lfni&xt=urn:ed2k:5ae257c47e9be1243ee32aabe408fb6b&xt=urn:aich:lmagnhcibvop7pp2rpn2tflbcyhs2g3x"
check "$TEST_RESULT" "$TEST_EXPECTED" .
# also test that '--check' verifies files in the current directory
mkdir magnet_dir && $rhash --magnet -a test1K.data > magnet_dir/t.magnet
TEST_RESULT=$( $rhash -vc magnet_dir/t.magnet 2>&1 | grep test1K.data )
TEST_EXPECTED="^test1K.data *OK"
match "$TEST_RESULT" "$TEST_EXPECTED"

new_test "test bsd format checking:   "
TEST_RESULT=$( $rhash --bsd -a test1K.data | $rhash -c --skip-ok --brief - 2>&1 )
check "$TEST_RESULT" "Everything OK"

new_test "test checking w/o filename: "
$rhash -p '%c\n%m\n%e\n%h\n%g\n%t\n%a\n' test1K.data > test1K.data.sum
TEST_RESULT=$( $rhash -c --brief test1K.data.sum 2>&1 | grep -v '^test1K.data.*OK' )
check "$TEST_RESULT" "Everything OK"

new_test "test checking embedded crc: "
printf 'A' > 'test_[D3D99E8B].data' && printf 'A' > 'test_[D3D99E8C].data'
# first verify checking an existing crc32 while '--embed-crc' option is set
TEST_RESULT=$( $rhash -C --simple 'test_[D3D99E8B].data' | $rhash -vc --embed-crc - 2>/dev/null | grep data )
match "$TEST_RESULT" "^test_.*OK" .
TEST_RESULT=$( $rhash -C --simple 'test_[D3D99E8C].data' | $rhash -vc --embed-crc - 2>/dev/null | grep data )
match "$TEST_RESULT" "^test_.*ERROR, embedded CRC32 should be" .
# second verify --check-embedded option
TEST_RESULT=$( $rhash --check-embedded 'test_[D3D99E8B].data' 2>/dev/null | grep data )
match "$TEST_RESULT" "test_.*OK" .
TEST_RESULT=$( $rhash --check-embedded 'test_[D3D99E8C].data' 2>/dev/null | grep data )
match "$TEST_RESULT" "test_.*ERR" .
mv 'test_[D3D99E8B].data' 'test.data'
# test --embed-crc and --embed-crc-delimiter options
TEST_RESULT=$( $rhash --simple --embed-crc --embed-crc-delimiter=_ 'test.data' 2>/dev/null )
check "$TEST_RESULT" "d3d99e8b  test_[D3D99E8B].data"
rm 'test_[D3D99E8B].data' 'test_[D3D99E8C].data'

new_test "test checking recursively:  "
mkdir -p check/a && cp test1K.data check/a/b.data
echo "a/b.data B70B4C26" > check/b.sfv
TEST_RESULT=$( $rhash -Crc check/ | grep b.data )
match "$TEST_RESULT" "^a/b.data *OK" .
echo "B70B4C26" > check/a/b.data.crc32
TEST_RESULT=$( $rhash --crc-accept=.crc32 -Crc check/a | grep "data.*OK" )
match "$TEST_RESULT" "^check/a.b.data *OK" .
# test that hash-files specified explicitly by command line are checked
# in the current directory even with '--recursive' option
echo "test1K.data B70B4C26" > check/t.sfv
TEST_RESULT=$( $rhash -Crc check/t.sfv | grep "data.*OK" )
match "$TEST_RESULT" "^test1K.data *OK"

new_test "test wrong sums detection:  "
$rhash -p '%c\n%m\n%e\n%h\n%g\n%t\n%a\n%w\n' -m WRONG > t.sum
TEST_RESULT=$( $rhash -vc t.sum 2>&1 | grep 'OK' )
check "$TEST_RESULT" ""
rm t.sum

new_test "test missig files:          "
rm -f a.txt b.txt
printf "00000000 a.txt\\n00000000 test-empty.file\\n00000000 b.txt" > c.sfv
TEST_RESULT=$( $rhash --missing c.sfv 2>&1 | tr -d '\r' | tr '\n' '@' )
check "$TEST_RESULT" "a.txt@b.txt@"

new_test "test unverified files:      "
rm -rf d/ && mkdir d
touch d.txt d/a.txt
printf "00000000 d.txt\\n00000000 d/b.txt" > d.sfv
TEST_RESULT=$( $rhash -r --unverified d.sfv d.txt test-empty.file d/ 2>&1 | tr -d '\r' | tr '\n' '@' )
match "$TEST_RESULT" "^test-empty.file@d.a.txt@\$"

new_test "test update:                "
TEST_RESULT=$( $rhash -r --simple --update d.sfv d.txt test-empty.file d/ 2>&1 | tr -d '\r' | tr '\n' '@' )
check "$TEST_RESULT" "Updated: d.sfv@"

new_test "test *accept options:       "
mkdir -p test_dir/a && touch test_dir/a/file.txt test_dir/a/file.bin
# correctly handle MINGW posix path conversion
mingw_or_ucrt && SLASH=// || SLASH="/"
# test also --path-separator option
TEST_RESULT=$( $rhash -rC --simple --accept=.bin --path-separator=$SLASH test_dir )
check "$TEST_RESULT" "00000000  test_dir/a/file.bin" .
TEST_RESULT=$( $rhash -rC --simple --accept=.txt --path-separator=\\ test_dir/a )
check "$TEST_RESULT" "00000000  test_dir\\a\\file.txt" .
TEST_RESULT=$( $rhash -rc --crc-accept=.bin test_dir 2>/dev/null | sed -n '/Verifying/s/-//gp' )
match "$TEST_RESULT" "( Verifying test_dir.a.file\\.bin )"

new_test "test ignoring of log files: "
touch t1.out t2.out
TEST_RESULT=$( $rhash -C --simple t1.out t2.out -o t1.out -l t2.out 2>/dev/null )
check "$TEST_RESULT" "" .
TEST_RESULT=$( $rhash -c t1.out t2.out -o t1.out -l t2.out 2>/dev/null )
check "$TEST_RESULT" ""
rm t1.out t2.out

new_test "test creating torrent file: "
TEST_RESULT=$( $rhash --btih --torrent --bt-private --bt-piece-length=512 --bt-announce=http://tracker.org/ test1K.data 2>/dev/null )
check "$TEST_RESULT" "29f7e9ef0f41954225990c513cac954058721dd2  test1K.data"
rm test1K.data.torrent

new_test "test exit code:             "
rm -f none-existent.file
test -f none-existent.file && print_failed .
$rhash -H none-existent.file 2>/dev/null
check "$?" "1" .
$rhash -c none-existent.file 2>/dev/null
check "$?" "1" .
A_SFV="$RHASH_TMP/a.sfv"
printf "00000000 none-existent.file\\n00000000 test-empty.file\\n" > "$A_SFV"
$rhash -c "$A_SFV" >/dev/null
check "$?" "1" .
$rhash -c --ignore-missing "$A_SFV" >/dev/null
check "$?" "0" .
$rhash -H test1K.data >/dev/null
check "$?" "0"
UNWRITABLE_FILE="$RHASH_TMP/test-unwritable.file"
printf "" > "$UNWRITABLE_FILE" && chmod a-w "$UNWRITABLE_FILE"
# check if the file is really unwritable, since the superuser still can write to it
if ! test -w "$UNWRITABLE_FILE" ; then
 $rhash -o "$UNWRITABLE_FILE" -H test1K.data 2>/dev/null
 check "$?" "2" .
fi
rm -f "$UNWRITABLE_FILE"

# check if any test failed
if [ $fail_cnt -gt 0 ]; then
  printf "Failed $fail_cnt checks\n"
  exit 1 # some tests failed
fi

exit 0 # success
