#/bin/bash
# vcsh-home bootstrap file

SELF="$BASH_SOURCE"

if [ "$1" == "-v" -o "$1" == "--verbose" ]; then
	VERBOSE=1
	shift
fi

check_cmds() {
	for EACH_COMMAND in "$@"; do
		[ "$VERBOSE" ] && echo -e "Checking for command $EACH_COMMAND"
		if ! type "$EACH_COMMAND" >/dev/null 2>&1; then
			echo "$SELF: command $EACH_COMMAND is not available."
			exit 1
		fi
	done
}

abort() {
	echo $@
	exit 1
}

bootstrap() {
	check_cmds git

	# Create work directory
	[ "$VERBOSE" ] && echo -e "Creating work directory"
	[ -e "$WORKDIR" ] && abort "Directory $TEMPDIR exists already. Are you sure you need to bootstrap?"
	mkdir -p "$WORKDIR/git" || abort "Error creating working directory."

	# Fetch the needed tools
	[ "$VERBOSE" ] && echo -e "Cloning vcsh repository"
	git clone git://github.com/RichiH/vcsh.git "${WORKDIR}/git/vcsh" && [ -f "${WORKDIR}/git/vcsh/vcsh" ] \
		|| abort "Unable to fetch vcsh."

	# Use the downloaded tools to fetch the basic configuration
	[ "$VERBOSE" ] && echo -e "Cloning vcsh configuration repository"
	cd
	"${WORKDIR}/git/vcsh/vcsh" clone git://github.com/ealimonda/${CONFREPO}.git ${CONFREPO} \
		|| abort -e "\n\nErrors found while fetching the vcsh configuration."\
		"\nPlease check the error log."\
		"\n(you might just need to run \"${WORKDIR}/git/vcsh/vcsh run ${CONFREPO} git pull\" to fix it.)"\
		"\nThen run again \"${SELF} guess\"."
	[ "$VERBOSE" ] && echo -e "Adding to the enabled repositories"
	linkconfigrepo
}

linkconfigrepo() {
	linkrepo "$CONFREPO" all
	echo "Bootstrapped.  Please check the repos in \"${CONFDIR}/conf-available\" and enable the ones you need, then run \"$SELF get\""
}

linkrepo() {
	local CONFBSDIR="${CONFDIR}/conf-bootstrap"
	local CONFENDIR="${CONFDIR}/conf-enabled"
	[ "$VERBOSE" ] && echo "Linking repository $2 to $1"
	[ -d "$CONFBSDIR" -a -d "$CONFENDIR" ] || abort "Missing directories in $CONFBSDIR and/or $CONFENDIR"
	[ -f "${CONFDIR}/conf-available/$1.conf" ] || abort "Missing configuration for repository $1."
	if [ "$2" == "all" -o "$2" == "enabled" ]; then
		cd "${CONFENDIR}" && ln -sfn "../conf-available/$1.conf" "$1.conf"
	fi
	if [ "$2" == "all" -o "$2" == "bootstrap" ]; then
		cd "${CONFBSDIR}" && ln -sfn "../conf-available/$1.conf" "$1.conf"
	fi
}

unlinkrepo() {
	local CONFBSDIR="${CONFDIR}/conf-bootstrap"
	[ "$VERBOSE" ] && echo "Unlinking repository $1 from bootstrap directory"
	[ -d "$CONFBSDIR" ] || abort "Missing directories in $CONFBSDIR."
	[ -f "${CONFBSDIR}/$1.conf" ] || abort "Missing configuration for repository $1."
	rm "${CONFBSDIR}/$1.conf"
}

getrepos() {
	check_cmds git vcsh
	local PENDING=0
	local REPOS_CLONED=()
	[ "$VERBOSE" ] && echo "Checking for available cloned repositories..."
	while read LINE; do
		REPOS_CLONED+=("$LINE")
	done < <( vcsh list )
	[ "$VERBOSE" ] && echo "Checking for enabled configurations to fetch..."
	if cd "${CONFDIR}/conf-enabled"; then
		getenabled "${REPOS_CLONED[@]}"
		PENDING+=$?
	else
		echo "conf-enabled folder not found.  Skipping."
	fi
	[ "$VERBOSE" ] && echo "Checking for downloaded repositories to bootstrap..."
	if cd "${CONFDIR}/conf-bootstrap"; then
		getbootstrap "${REPOS_CLONED[@]}"
		PENDING+=$?
	else
		echo "conf-bootstrap folder not found.  Skipping."
	fi
	if [ "$PENDING" -gt 0 ]; then
		abort "No action taken.  Please check your repository dependencies."
	fi
	echo "Done.  No further action needed."
}

getenabled() {
	local REPOS_ENABLED=()
	local REPOS_CLONED=( "$@" )
	local REPO_URL=
	local REPO_DEPS=
	local NAME=
	local RETVAL=0
	# Enabled, but not cloned configs
	for EACH_CONFIG in *.conf; do
		[ "$EACH_CONFIG" == "*.conf" ] && break
		[ "$VERBOSE" ] && echo "Testing $EACH_CONFIG"
		NAME="$(basename "$EACH_CONFIG" .conf)"
		for EACH in "${REPOS_CLONED[@]}"; do
			# If found, skip to the next EACH_CONFIG
			[ "$EACH" == "$NAME" ] && continue 2
		done
		# Not found, so add it to the list
		REPOS_ENABLED+=("$NAME")
		[ "$VERBOSE" ] && echo "...Added"
	done
	for EACH_REPO in "${REPOS_ENABLED[@]}"; do
		[ "$VERBOSE" ] && echo "Verifying $EACH_REPO"
		REPO_URL=
		REPO_DEPS=
		source <( egrep '^REPO_(URL|DEPS)=' "$EACH_REPO.conf" )
		[ -z "$REPO_URL" ] && abort "Broken configuration for $EACH_REPO (no URL set)"
		for EACH_DEP in "${REPO_DEPS[@]}"; do
			[ "$VERBOSE" ] && echo "  Verifying dependency $EACH_DEP"
			for EACH in "${REPOS_CLONED[@]}"; do
				[ "$VERBOSE" ] && echo "    -> $EACH"
				# Found, skip to the next EACH_DEP
				[ "$EACH" == "$EACH_DEP" ] && continue 2
			done
			# Unmet dependency. Let's skip this one for now
			echo "Postponing $EACH_REPO (unmet dependencies)"
			(( RETVAL++ ))
			continue 2
		done
		# Everything is ready.  Let's do it
		echo "Cloning $REPO_URL as $EACH_REPO..."
		cd
		vcsh clone "$REPO_URL" "$EACH_REPO"
		echo -e "\nDone.  Please check the log for errors, then rerun this command again\n"\
			"A typical resolution workflow is:\n"\
			" 1$ vcsh $EACH_REPO\n"\
			" 2$ git pull\n"\
			" 2$ git reset --mixed"\
			" 2$ git status # (add, rm, checkout files)\n"\
			" 2$ <C-d>"
		exit 0
	done
	return $RETVAL
}

getbootstrap() {
	local REPOS_BOOTSTRAP=()
	local REPOS_CLONED=( "$@" )
	local BOOTSTRAP_URL=
	local BOOTSTRAP_DEPS=
	local NAME=
	local RETVAL=0
	# Repos pending bootstrap
	for EACH_CONFIG in *.conf; do
		[ "$EACH_CONFIG" == "*.conf" ] && break
		[ "$VERBOSE" ] && echo "Testing $EACH_CONFIG"
		NAME="$(basename "$EACH_CONFIG" .conf)"
		for EACH in "${REPOS_CLONED[@]}"; do
			# If found, add to the list
			[ "$EACH" != "$NAME" ] && continue
			# Found, so add it to the list
			[ "$VERBOSE" ] && echo "...Added"
			REPOS_BOOTSTRAP+=("$NAME")
			break 2
		done
		# Not found, print a warning message and continue
		echo "Warning: $NAME is in the list of repositories to bootstrap but it was not found."
	done
	for EACH_REPO in "${REPOS_BOOTSTRAP[@]}"; do
		[ "$VERBOSE" ] && echo "Verifying $EACH_REPO"
		BOOTSTRAP_URL=
		BOOTSTRAP_DEPS=
		source <( egrep '^BOOTSTRAP_(URL|DEPS)=' "$EACH_REPO.conf" )
		[ -z "$BOOTSTRAP_URL" ] && abort "Broken configuration for $EACH_REPO (no URL set)"
		for EACH_DEP in "${BOOTSTRAP_DEPS[@]}"; do
			[ "$VERBOSE" ] && echo "  Verifying dependency $EACH_DEP"
			for EACH in "${REPOS_CLONED[@]}"; do
				[ "$VERBOSE" ] && echo "    -> $EACH"
				# Found, skip to the next EACH_DEP
				[ "$EACH" == "$EACH_DEP" ] && continue 2
			done
			# Unmet dependency. Let's skip this one for now
			echo "Postponing $EACH_REPO (unmet dependencies)"
			(( RETVAL++ ))
			continue 2
		done
		# Everything is ready.  Let's do it
		echo "Editing $EACH_REPO URL to $BOOTSTRAP_URL..."
		cd
		vcsh run "$EACH_REPO" git remote set-url origin "$BOOTSTRAP_URL"
		unlinkrepo "$EACH_REPO"
		echo -e "\nDone.  Please check the log for errors, then rerun this command again"
		exit 0
	done
	return $RETVAL
}

guess() {
	[ "$VERBOSE" ] && echo -n "Checking action to do... "
	if [ ! -e "$WORKDIR" ]; then
		[ "$VERBOSE" ] && echo "bootstrap"
		bootstrap
	elif [ ! -e "${CONFDIR}/conf-enabled/${CONFREPO}.conf" ]; then
		[ "$VERBOSE" ] && echo "completing bootstrap"
		linkconfigrepo
	else
		[ "$VERBOSE" ] && echo "fetching repositories"
		getrepos
	fi
}

[ -z "$1" ] && abort "What do you want to do? (bootstrap|get|continue)"

WORKDIR="${HOME}/.dotfiles.d"
CONFDIR="${HOME}/.config/vcsh"
CONFREPO="dotfiles-vcsh"
[ "$VERBOSE" ] && echo -e "\$WORKDIR=$WORKDIR\n\$CONFDIR=$CONFDIR"

case "$1" in
	guess)
		[ "$VERBOSE" ] && echo -e "Running in guess mode"
		guess
		;;
	bootstrap)
		[ "$VERBOSE" ] && echo -e "Running in bootstrap mode"
		bootstrap
		;;
	get)
		[ "$VERBOSE" ] && echo -e "Running in get mode"
		getrepos
		;;
esac

