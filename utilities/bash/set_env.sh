#!/bin/bash

function how_to_use() {
    cat <<EOF

   `basename $0` [action] [option]
   to set up the SixDesk environment

   actions (mandatory, one of the following):
   -s              set up new study or update existing one according to local
                       version of input files (${necessaryInputFiles[@]})
                   NB: the local input files (${necessaryInputFiles[@]})
                       will be parsed, used and saved in studies/
   -d <study_name> load existing study.
                   NB: the input files (${necessaryInputFiles[@]})
                       in studies/<study_name> will be parsed, used and saved in sixjobs
   -n              retrieve input files (${necessaryInputFiles[@]}) from template dir
                       to prepare a brand new study. The template files will
                       OVERWRITE the local ones. The template dir is:
           ${SCRIPTDIR}/templates/input
   -N <workspace>  create and initialise a new workspace in the current dir
                   with the workspace, please specify also the scratch name, eg
           -N scratch0/wTest
                   the workspace will be populated with template files as checked-out
                       with git from repo:
           ${origRepoForSetup}
                       branch:
           ${origBranchForSetup}
   -U      unlock dirs necessary to the script to run
           PAY ATTENTION when using this option, as no check whether the lock
              belongs to this script or not is performed, and you may screw up
              processing of another script

   options (optional)
   -p      platform name (when running many jobs in parallel)
           recognised platforms: LSF, BOINC, HTCONDOR
           this option allows to override the value in sixdeskenv, with no need
              for the user to manually change the corresponding variable. Similarly,
              the variable is NOT automatically updated by the script
   -e      just parse the concerned input files (${necessaryInputFiles[@]}),
               without overwriting
   -l      use fort.3.local. This file will be added to the list of necessary
               input files only in case this flag will be issued.
   -P      python path
   -v      verbose (OFF by default)

EOF
}

function basicChecks(){

    # - running dir
    if [ "$sixdeskroot" != "sixjobs" ] ; then
	sixdeskmess -1 "This script must be run in the directory sixjobs!!!"
	sixdeskexit 1
    fi

    # - make sure we have a studies directory
    if ${lset} ; then
	[ -d studies ] || mkdir studies
    elif ${lload} ; then
	sixdeskInspectPrerequisites ${lverbose} studies -d
    fi
    if [ $? -gt 0 ] ; then
	sixdeskexit 2
    fi

    # - make sure that, in case of loading, we have the concerned directory in studies:
    if ${lload} ; then
	sixdeskInspectPrerequisites ${lverbose} ${envFilesPath} -d
	if [ $? -gt 0 ] ; then
	    sixdeskmess -1 "Dir containing input files for study $currStudy not found!!!"
	    sixdeskmess -1 "Expected: ${envFilesPath}"
	    sixdeskexit 3
	fi
    fi

    return 0
}

function consistencyChecks(){

    # - make sure we are in the correct workspace
    if [ -z "${workspace}" ] ; then
	sixdeskmess -1 "Workspace not declared in $envFilesPath/sixdeskenv!!!"
	sixdeskexit 5
    fi
    local __cworkspace=`basename $sixdeskwhere`
    if [ "${workspace}" != "${__cworkspace}" ] ; then
	sixdeskmess -1 "Workspace mismatch: ${workspace} (from sixdeskenv) different from ${__cworkspace} (from current path)!!!"
	sixdeskmess -1 "Check the workspace definition in $envFilesPath/sixdeskenv."
	sixdeskexit 6
    fi

    # - study:
    #   . make sure we have one in sixdeskenv
    if [ -z "${LHCDescrip}" ] ; then
	sixdeskmess -1 "LHCDescrip not declared in $envFilesPath/sixdeskenv!!!"
	sixdeskexit 7
    fi
    #   . make sure it corresponds to the expected one
    if ${lload} ; then
	if [ "${LHCDescrip}" != "${currStudy}" ] ; then
	    sixdeskmess -1 "Study mismatch: ${LHCDescrip} (from sixdeskenv) different from $currStudy (command-line argument)!!!"
	    sixdeskexit 8
	fi
    fi

    # - sixtrack app name
    sixDeskCheckAppName ${appName}
    if [ $? -ne 0 ] ; then
	sixdeskexit 9
    fi

    return 0
}

function getInfoFromFort3Local(){
    export fort3localLines=`awk 'NF' ${envFilesPath}/fort.3.local`
    local __activeLines=`echo "${fort3localLines}" | grep -v '/'`
    local __firstActiveBlock=`echo "${__activeLines}" | head -1 | cut -c1-4`
    local __otherActiveBlocks=`echo "${__activeLines}" | grep -A1 NEXT | grep -v NEXT | grep -v '^\-\-' | cut -c1-4`
    local __allActiveBlocks="${__firstActiveBlock} ${__otherActiveBlocks}"
    __allActiveBlocks=( ${__allActiveBlocks} )
    if [ ${#__allActiveBlocks[@]} -gt 0 ] ; then
	sixdeskmess="active blocks in ${envFilesPath}/fort.3.local:"
	sixdeskmess
	for tmpActiveBlock in ${__allActiveBlocks[@]} ; do
	    sixdeskmess="- ${tmpActiveBlock}"
	    sixdeskmess
	done
	local __nLines=`echo "${__activeLines}" | wc -l`
	sixdeskmess="for a total of ${__nLines} ACTIVE lines."
	sixdeskmess
    fi
}

function setFurtherEnvs(){
    # set exes
    sixdeskSetExes
    # scan angles:
    lReduceAngsWithAmplitude=false
 
    if [ -n "${reduce_angs_with_aplitude}" ] ; then
        sixdeskmess -1 "wrong spelling of reduce_angs_with_amplitude. Please correct it for future use"
        reduce_angs_with_amplitude=${reduce_angs_with_aplitude}
    fi   
    
    if [ -z "${reduce_angs_with_amplitude}" ]; then
        reduce_angs_with_amplitude=0         
    elif (( $(echo "${reduce_angs_with_amplitude}" | awk '{print ($1 >=0)}') )); then 
        if [ ${long} -ne 1 ]; then
            sixdeskmess -1 "reduced angles with amplitudes available only for long simulations!"
	    sixdeskexit 9
        else
            if [ ${kinil} -ne 1 ] || [ ${kendl} -ne ${kmaxl} ] || [ ${kstep} -ne 1 ]; then
                sixdeskmess -1 "reduced angles with amplitudes available only for kmin=1, kend=kmax and kstep=1"
		sixdeskexit 10
            elif (( $(echo "${reduce_angs_with_amplitude} ${ns2l}" | awk '{print ($1 >= $2)}') )); then
                sixdeskmess -1 "reduced angles with amplitudes flag greater than maximum amplitude. Please de-activate the flag"
		sixdeskexit 11
            else 
                lReduceAngsWithAmplitude=true
            fi 
        fi
    else
        sixdeskmess -1 "reduced angles with amplitudes set to negative value. Flag de-activated"
    fi
    export totAngle=90
    export lReduceAngsWithAmplitude
}

# ==============================================================================
# main
# ==============================================================================

# ------------------------------------------------------------------------------
# preliminary to any action
# ------------------------------------------------------------------------------
# - get path to scripts (normalised)
if [ -z "${SCRIPTDIR}" ] ; then
    SCRIPTDIR=`dirname $0`
    SCRIPTDIR="`cd ${SCRIPTDIR};pwd`"
    export SCRIPTDIR=`dirname ${SCRIPTDIR}`
fi
# ------------------------------------------------------------------------------

# - necessary input files
necessaryInputFiles=( sixdeskenv sysenv )

# actions and options
lset=false
lload=false
lcptemplate=false
lcrwSpace=false
loverwrite=true
lverbose=false
llocalfort3=false
lunlock=false
currPlatform=""
currStudy=""
tmpPythonPath=""
origRepoForSetup='https://github.com/amereghe/SixDesk.git'
origBranchForSetup=`git --git-dir=${SCRIPTDIR}/../.git branch | grep '*' | awk '{print ($NF)}'`

# variables set based on parsing fort.3.local

nActions=0

# get options (heading ':' to disable the verbose error handling)
while getopts  ":hsvld:ep:P:nN:U" opt ; do
    case $opt in
	h)
	    how_to_use
	    exit 1
	    ;;
	s)
	    # set study (new/update/switch)
	    lset=true
	    let nActions+=1
	    ;;
	d)
	    # load existing study
	    lload=true
	    currStudy="${OPTARG}"
	    let nActions+=1
	    ;;
	n) 
	    # copy input files from template dir
	    lcptemplate=true
	    let nActions+=1
	    ;;
	N)
	    # create workspace
	    lcrwSpace=true
	    wSpaceName="${OPTARG}"
	    ;;
	e)
	    # do not overwrite
	    loverwrite=false
	    ;;
	p)
	    # the user is requesting a specific platform
	    currPlatform="${OPTARG}"
	    ;;
	l)
	    # use fort.3.local
	    llocalfort3=true
	    ;;
	P)
	    # the user is requesting a specific path to python
	    tmpPythonPath="${OPTARG}"
	    ;;
	U)
	    # unlock currently locked folder (optional action)
	    lunlock=true
	    ;;
	v)
	    # verbose
	    lverbose=true
	    ;;
	:)
	    how_to_use
	    echo "Option -$OPTARG requires an argument."
	    exit 1
	    ;;
	\?)
	    how_to_use
	    echo "Invalid option: -$OPTARG"
	    exit 1
	    ;;
    esac
done
shift "$(($OPTIND - 1))"
# user's request
# - actions
if ! ${lset} && ! ${lload} && ! ${lcptemplate} && ! ${lunlock} && ! ${lcrwSpace} ; then
    how_to_use
    echo "No action specified!!! aborting..."
    exit
elif [ ${nActions} -gt 1 ] ; then
    how_to_use
    echo "Please choose only one action!!! aborting..."
    exit
fi
# - clean options in case of brand new study
if ${lcptemplate} ; then
    if [ -n "${currPlatform}" ] ; then
	echo "--> brand new study: -p option with argument ${currPlatform} is switched off."
	currPlatform=""
    fi
fi
# - options
if [ -n "${currStudy}" ] ; then
    echo "--> User required a specific study: ${currStudy}"
fi
if [ -n "${currPlatform}" ] ; then
    echo "--> User required a specific platform: ${currPlatform}"
fi
if ${llocalfort3} ; then
    echo ""
    echo "--> User requested inclusion of fort.3.local"
    echo ""
    necessaryInputFiles=( sixdeskenv sysenv fort.3.local )
fi

# ------------------------------------------------------------------------------
# preparatory steps
# ------------------------------------------------------------------------------

export sixdeskhostname=`hostname`
export sixdeskname=`basename $0`
export sixdesknameshort=`echo "${sixdeskname}" | cut -b 1-15`
export sixdeskecho="yes!"
export sixdesklevel=-1
if [ ! -s ${SCRIPTDIR}/bash/dot_profile ] ; then
    echo "dot_profile is missing!!!"
    exit 1
fi
# - load environment
source ${SCRIPTDIR}/bash/dot_profile
# - stuff specific to node where user is running:
sixdeskSetLocalNodeStuff

# - set up new workspace
if ${lcrwSpace} ; then
    if [ `echo "${wSpaceName}" | awk 'BEGIN{FS="/"}{print (NF)}'` -ne 2 ] ; then
	how_to_use
	echo "invalid workspace specification!"
	exit 1
    fi
    sixdeskmess -1 "requested generation of new workspace:"
    sixdeskmess -1 "- current path: $PWD"
    sixdeskmess -1 "- <scratch_dir>/<workspace>: ${wSpaceName}"
    if [ -d ${wSpaceName} ] ; then
	how_to_use
	sixdeskmess -1 "workspace ${wSpaceName} already exists!"
	exit 1
    else
	mkdir -p ${wSpaceName}
	cd ${wSpaceName}
	if [ `which git 2>/dev/null | wc -l` -eq 1 ] ; then
	    sixdeskmess -1 "--> using git to initialise sixjobs"
	    git init
	    git config core.sparseCheckout true
	    cat > .git/info/sparse-checkout <<EOF
sixjobs/control_files/*
sixjobs/mask/*
sixjobs/sixdeskTaskIds/*
sixjobs/studies/*
EOF
	    git remote add -f origin ${origRepoForSetup}
	    git checkout ${origBranchForSetup}
	else
	    origDir=`dirname ${SCRIPTDIR}`/sixjobs
	    sixdeskmess -1 "--> initialising sixjobs from ${origDir}"
	    cp -r ${origDir} .
	fi
	cd - 2>&1 > /dev/null
	cd ${wSpaceName}/sixjobs
	touch sixdesklock
	touch studies/sixdesklock
	cd - 2>&1 > /dev/null
    fi
    [ -e `basename ${wSpaceName}` ] || ln -s ${wSpaceName}
    if [ ${nActions} -eq 0 ] ; then
	sixdeskmess -1 "requested only initilising workspace. Exiting..."
	exit 0
    fi
    cd ${wSpaceName}/sixjobs
fi

export sixdeskroot=`basename $PWD`
export sixdeskwhere=`dirname $PWD`
# Set up some temporary values until we parse input files
# Don't issue lock/unlock debug text (use 2 for that)
export sixdesklogdir=""
export sixdeskhome="."

# - locking dirs
if ${lcptemplate} ; then
    lockingDirs=( . )
else
    lockingDirs=( . studies )
fi

# - unlocking
if ${lunlock} ; then
    sixdeskunlockAll
    if ! ${lset} && ! ${lload} && ! ${lcptemplate} ; then
	sixdeskmess -1 "requested only unlocking. Exiting..."
	exit 0
    fi
fi
   
# - path to input files
if ${lset} ; then
    envFilesPath="."
elif ${lload} ; then
    envFilesPath="studies/${currStudy}"
fi

# - basic checks (i.e. dir structure)
basicChecks
if [ $? -gt 0 ] ; then
    sixdeskexit 4
fi

# ------------------------------------------------------------------------------
# actual operations
# ------------------------------------------------------------------------------

# - lock dirs
sixdesklockAll

if ${lcptemplate} ; then

    sixdeskmess -1 "copying here template files for brand new study"
    sixdeskmess -1 "template input files from ${SCRIPTDIR}/templates/input"

    for tmpFile in ${necessaryInputFiles[@]} ; do
	# preserve original time stamps
	cp -p ${SCRIPTDIR}/templates/input/${tmpFile} .
	sixdeskmess 2 "${tmpFile}"
    done
    tmpDir=`readlink -f $PWD`
    tmpDir=`dirname ${tmpDir}`
    workspace=`basename ${tmpDir}`
    tmpDir=`dirname ${tmpDir}`
    scratchDir=${tmpDir}
    tmpDir=`dirname ${tmpDir}`
    baseDir=${tmpDir}
    sed -i -e "s#^export workspace=.*#export workspace=${workspace}#" \
	   -e "s#^export basedir=.*#export basedir=${baseDir}#" \
	   -e "s#^export scratchdir=.*#export scratchdir=${scratchDir}#" sixdeskenv

else

    # - make sure we have sixdeskenv/sysenv/fort.3.local files
    sixdeskInspectPrerequisites ${lverbose} $envFilesPath -s ${necessaryInputFiles[@]}
    if [ $? -gt 0 ] ; then
        sixdeskmess -1 "not all necessary files are in $envFilesPath dir:"
        sixdeskmess -1 "missing files: ${necessaryInputFiles[@]}"
        sixdeskmess -1 "status of dir:"
        \ls -ltrh $envFilesPath
	sixdeskexit 4
    fi

    # - source active sixdeskenv/sysenv
    source ${envFilesPath}/sixdeskenv
    source ${envFilesPath}/sysenv
    if ${llocalfort3} ; then
	getInfoFromFort3Local
    fi

    # - perform some consistency checks on parsed info
    consistencyChecks

    # - set further envs
    setFurtherEnvs

    # - save input files
    if ${loverwrite} ; then
	__lnew=false
	if ${lset} ; then
	    if ! [ -d studies/${LHCDescrip} ] ; then
		__lnew=true
		mkdir studies/${LHCDescrip}
	    fi
	fi

        # We now call update_sixjobs in case there were changes
        #    and to create for example the logfile directories
	source ${SCRIPTDIR}/bash/update_sixjobs
	if ! ${__lnew} ; then
            # and now we can check 
	    source ${SCRIPTDIR}/bash/check_envs
	fi
	
	if ${lset} ; then
	    cp ${envFilesPath}/sixdeskenv studies/${LHCDescrip}
	    cp ${envFilesPath}/sysenv studies/${LHCDescrip}
	    if ${llocalfort3} ; then
		cp ${envFilesPath}/fort.3.local studies/${LHCDescrip}
	    fi
	    if ${__lnew} ; then
  	        # new study
		sixdeskmess -1 "Created a NEW study $LHCDescrip"
	    else
 	        # updating an existing study
		sixdeskmess -1 "Updated sixdeskenv/sysenv(/fort.3.local) for $LHCDescrip"
	    fi
	elif ${lload} ; then
	    cp ${envFilesPath}/sixdeskenv .
	    cp ${envFilesPath}/sysenv .
	    if ${llocalfort3} ; then
		cp ${envFilesPath}/fort.3.local .
	    fi
	    sixdeskmess -1 "Switched to study $LHCDescrip"
	fi
    fi

    # - overwrite platform
    if [ -n "${currPlatform}" ] ; then
	platform=$currPlatform
    fi
    sixdeskSetPlatForm $platform
    if [ $? -ne 0 ] ; then
	sixdeskexit 10
    fi

    # - set python path
    if [ -n "${tmpPythonPath}" ] ; then
	# overwrite what was stated in sixdeskenv/sysenv
	pythonPath=${tmpPythonPath}
    fi
    sixdeskDefinePythonPath ${pythonPath}

    # - useful output
    PTEXT="[${sixdeskplatform}]"
    STEXT="[${LHCDescrip}]"
    WTEXT="[${workspace}]"
    BTEXT="no BNL flag"
    if [ "$BNL" != "" ] ; then
	BTEXT="BNL flag active"
    fi
    NTEXT="[$sixdeskhostname]"
    ETEXT="[$appName - ${SIXTRACKEXE}]"

    echo
    sixdeskmess -1 "STUDY          ${STEXT}"
    sixdeskmess -1 "WSPACE         ${WTEXT}"
    sixdeskmess -1 "PLATFORM       ${PTEXT}"
    sixdeskmess -1 "HOSTNAME       ${NTEXT}"
    sixdeskmess -1 "${BTEXT}"
    sixdeskmess -1 "APPNAME/EXE    ${ETEXT}"
    echo
    
    if [ -e "$sixdeskstudy"/deleted ] ; then
	if ${loverwrite} ; then
	    rm -f "$sixdeskstudy"/deleted
	else
	    sixdeskmess -1 "Warning! Study `basename $sixdeskstudy` has been deleted!!! Please restore it explicitely"
	fi
    fi

fi

# - unlock dirs
sixdeskunlockAll

if ! ${lcptemplate} ; then

    if ${lKerberos} ; then
        # - kinit, to renew kerberos ticket
        sixdeskRenewKerberosToken
    fi
    
    # - fs listquota
    echo ""
    if [[ "${sixdesktrack}" == "/afs"* ]] ; then
	sixdeskmess -1 " --> fs listquota ${sixdesktrack}:"
	tmpLines=`fs listquota ${sixdesktrack}`
	echo "${tmpLines}"
	#   check, and in case raise a warning
	fraction=`echo "${tmpLines}" | tail -1 | awk '{frac=$3/$2*100; ifrac=int(frac); if (frac-ifrac>0.5) {ifrac+=1} print (ifrac)}'`
	if [ ${fraction} -gt 90 ] ; then
	    sixdeskmess -1 "WARNING: your quota is above 90%!! pay attention to occupancy of the current study, in case of submission..."
	fi
    else
	sixdeskmess -1 " --> df -Th ${sixdesktrack}:"
	\df -Th ${sixdesktrack}
	sixdeskmess -1 " the above output is at your convenience, for you to check disk space"
    fi

fi