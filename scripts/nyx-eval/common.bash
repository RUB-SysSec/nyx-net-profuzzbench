# Available cores
mapfile -t cores < <(seq 0 51)

# Number of runs. Runs are numbered from 0.
runs=
target=
targetdir=
outdir=
snap_placement=none
no_seeds=0

# Default value for index of single runs; determines the output directory name.
single_index=0

dodebug=0
dryrun=0

# Contains PIDs of children (e.g. runs)
declare -A pids
# Set to 1 if interrupted by signal (e.g. Ctrl-C)
interrupted=0

# If 1 don't use shut_down as SIGINT handler
NOTRAP=${NOTRAP:-0}

# Path to Nyx-Net fuzzer
NYX_NET_FUZZER_DIR=${NYX_NET_FUZZER_DIR:-"$HOME/nyx-net/fuzzer/rust_fuzzer"}
NYX_NET_FUZZER_DEBUG_DIR=${NYX_NET_FUZZER_DEBUG_DIR:-"$HOME/nyx-net/fuzzer/rust_fuzzer_debug"}
NYX_NET_TARGETS_DIR=${NYX_NET_TARGETS_DIR:-"$HOME/nyx-net/targets/packed_targets"}

declare -A ports
ports['forked-daapd']=3689
ports['dcmtk']=5158
ports['dnsmasq']=5353
ports['tinydtls']=20220
ports['bftpd']=21
ports['lightftp']=2200
ports['proftpd']=21
ports['pure-ftpd']=21
ports['live555']=8554
ports['kamailio']=5060
ports['exim']=25
ports['openssh']=22
ports['openssl']=4433

ROOTDIR=$(readlink -f "$HEREDIR/../../")
FREECORESBIN="$ROOTDIR/freecores/target/release/freecores"

# Handler for SIGINT; also terminates all processes in $pids
function shut_down {
    if [ "${#pids[@]}" -gt 0 ]; then
        info "Killing ${!pids[*]}"
        kill -TERM "${!pids[@]}"
    fi
    interrupted=1
}

if [ "$NOTRAP" = 0 ]; then
    trap shut_down SIGINT
fi

# Colors and helper functions
red="\e[0;91m"
yellow="\e[0;33m"
blue="\e[0;94m"
green="\e[0;92m"
reset="\e[0m"
function error { echo -e "${red}[!] $1$reset"; }
function warn  { echo -e "${yellow}[!] $1$reset"; }
function debug { echo -e "${blue}[?] $1$reset"; }
function info  { echo -e "${green}[+]$reset $1"; }

function usage_flag {
    case $1 in
        r) echo "  -$1 number of trials / runs" ;;
        c) echo "  -$1 only a single trial on the given core (-r is ignored)" ;;
        i) echo "  -$1 sets the run index number (e.g. in [0,9]) if running with -c; see \$n for -d" ;;
        t) echo "  -$1 target to run; also expects the spec in /tmp/nyx_\$target" ;;
        d) echo "  -$1 directory where to place the outputs (it'll be \$outdir/out-\$target-\$n)" ;;
        *)
            >&2 error "Wrong usage_flag argument $1"
            exit 1
            ;;
    esac
}

function validate_posnum {
    local arg=$1 opt=$2
    if ! [[ ( "$arg" =~ [0-9]+ ) && ( "$arg" -gt 0 ) ]]; then
        >&2 error "Invalid value: -$opt expects a positive number."
        >&2 usage
    fi
}

function validate_posnum_z {
    local arg=$1 opt=$2
    if ! [[ ( "$arg" =~ [0-9]+ ) && ( "$arg" -ge 0 ) ]]; then
        >&2 error "Invalid value: -$opt expects a number greater or equal to zero."
        >&2 usage
    fi
}

function validate_outdir {
    outdir=${OPTARG}
    if [ $dryrun = 0 ] && [ ! -d "$outdir" ]; then
        >&2 error "Invalid value: -$opt expects a directory."
        >&2 usage
    fi
}

function no_arg_error {
    >&2 error "Must supply an argument to -$OPTARG."
    >&2 usage
}

function invalid_arg_error {
    >&2 error "Invalid option: -${OPTARG}."
    >&2 usage
}

function validate_core_or_runs {
    if [ -z "$single_core" ] && [ -z "$runs" ]; then
        >&2 error "Parameters -r or -c are required"
        >&2 usage
    elif [ -n "$single_core" ] && [ -n "$runs" ]; then
        >&2 error "Parameters -c and -r are mutually exclusive"
        >&2 usage
    fi
}

function validate_snap_placement {
    snap_placement=${OPTARG}
    if ! [[ "$snap_placement" =~ none|balanced|aggressive ]]; then
        >&2 error "Invalid value: -$opt expects one of 'none', 'balanced' or 'aggressive'"
        >&2 usage
    fi
}

function validate_nyx_spec {
    if [ $no_seeds = 1 ]; then
        targetdir="$NYX_NET_TARGETS_DIR/nyx_${target}_no_seeds"
    else
        targetdir="$NYX_NET_TARGETS_DIR/nyx_$target"
    fi
    if [ $dryrun = 0 ] && [ ! -d "$targetdir" ]; then
        >&2 error "Invalid value: -$opt expects a target for $NYX_NET_TARGETS_DIR/nyx_TARGET or nyx_TARGET_no_seeds."
        >&2 usage
    fi
}

# Sets array of free cores in $free; accepts available cores as $cores array.
# This also checks that the number of free cores is enough for $runs.
function get_free_cores {
    if [ ! -x "$FREECORESBIN" ]; then
        info "Compiling freecores utility"
        if ! (cd "$ROOTDIR/freecores" && cargo build --release > /dev/null 2>&1); then
            >&2 error "Could not compile freecores"
            exit 1
        fi
    fi

    mapfile -t free < <($FREECORESBIN -j10 -n "${cores[@]}" 2> /dev/null)
    if [ $dodebug = 1 ]; then
        debug "Free cores: ${free[*]}"
    fi

    if [ "${#free[@]}" -lt "$runs" ]; then
        >&2 error "Not enough cores to run $runs tasks: ${#free[@]}"
        exit 1
    fi
}

function get_outdir {
    local trial_idx=$1
    local fuzzer=$2
    if [ "$fuzzer" = "nyx" ]; then
        if [ "$snap_placement" = "none" ]; then
            printf "%s/out-%s-%03d" "$outdir" "$target" "$trial_idx"
        else
            printf "%s/out-%s-%s-%03d" "$outdir" "$target" "$snap_placement" "$trial_idx"
        fi
    else
        printf "%s/out-%s-%s-%03d" "$outdir" "$target" "$fuzzer" "$trial_idx"
    fi
}

function cd_and_cargo {
    local dir=$1
    if ! cd "$dir"; then
        >&2 error "Failed to cd to '$dir'"
        exit 1
    fi
    if ! cargo build --release > /dev/null 2>&1; then
        >&2 error "Failed to compile..."
        exit 1
    fi
}

# Wait for all processes in $pids to terminate.
function wait_all_children {
    local exit_code pid
    while true; do
        info "Waiting on ${!pids[*]}"
        wait -n "${!pids[@]}"
        exit_code=$?
        [ $interrupted = 1 ] && break
        info "Process exited with code $exit_code"
        for pid in "${!pids[@]}"; do
            if ! ps -p "$pid" > /dev/null; then
                unset "pids[$pid]"
            fi
        done
        [ "${#pids[@]}" -eq 0 ] && break
    done
}

# Make sure we leave no QEMU instances running.
function clean_qemu {
    if killall -9 qemu-system-x86_64 > /dev/null 2>&1; then
        info "Leftover QEMU instances killed"
    elif pgrep qemu-system-x86_64 > /dev/null 2>&1; then
        >&2 warn "Failed to kill leftover QEMU instances"
    else
        info "No leftover QEMU instances"
    fi
}
