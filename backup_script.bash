#!/bin/bash
# |-------------------------------------------------------------------------| #
# |                           Program Information                           | #
# |-------------------------------------------------------------------------| #
# | File         : backup_script.bash                                       | #
# | PL           : bash                                                     | #
# | Purpose      : script to automate VM backups on xenserver               | #
# | Course       : PR lab xenserver                                         | #
# | Date         : 2013_12_17                                               | #
# | Author       : Constantinos Solomonides                                 | #
# | +              solomoni@ceid.upatras.gr                                 | #
# | +              ceid3549@upnet.gr                                        | #
# |-------------------------------------------------------------------------| #
# | keywords     : xenserver prlab backup automatic cronjob                 | #
# |-------------------------------------------------------------------------| #
# | References:                                                             | #
# | -----------                                                             | #
# | 1. Xenserver Admin documentation guide                                  | #
# |    http://support.citrix.com/article/CTX137828                          | #
# | 2. snapback.sh 1.4, Simple script to create regular snapshot-based      | #
# |       backups for Citrix Xenserver by Mark Round                        | #
# |     http://www.markround.com/snapback                                   | #
# |-------------------------------------------------------------------------| #
# | Changelog:                                                              | #
# | ----------                                                              | #
# | 2013_12_17 :                                                            | #
# |             1. Script created.                                          | #
# |             2. Pseudocode general description added.                    | #
# |             3. List of TODO's added.                                    | #
# | 2013_12_30 :                                                            | #
# |             1. Functions implemented. One helper function was added.    | #
# | 2014_01_02 :                                                            | #
# |             1. Version 0.1 is completed. After confirming correctness   | #
# |                 of code, it will be run to test.                        | #
# | 2014_01_09 :                                                            | #
# |             1. Script has been de-bugged and is being run under         | #
# |                 observation to monitor results.                         | #
# |             2. Tested and running. Todos remain to be completed before  | #
# |                 script is given release status.                         | #
# | 2014_01_10 :                                                            | #
# |             1. Added handling of offline / online backups (backup-live) | #
# |                 in the backup procedure.                                | #
# |             2. Added safeguards to remove the temporary snaphots and    | #
# |                 restart temporarily stopped VMs in case of interrupt.   | #
# |             3. Corrected problem of multiple backups if run more than   | #
# |                 once on the same day.                                   | #
# |             4. Created functions to set / get global variables so that  | #
# |                 cleanup tasks can be communicated across functions.     | #
# | 2014_01_13 :                                                            | #
# |             1. Added four new function prototypes to implement.         | #
# |             2. Added option if only live should be backed up.           | #
# | 2014_01_15 :                                                            | #
# |             1. Added sr choice script-wise and per VM.                  | #
# |             2. Added db metadata and vm-list information.               | #
# | 2014_01_18 :                                                            | #
# |             1. Corrected get_should_stop_vm to return appropriate truth | #
# |                 values (was returning inverted ones.)                   | #
# |             2. Added disclaimer.                                        | #
# |             3. Added copyright and licence inforation.                  | #
# | 2014_01_21 :                                                            | #
# |             1. Added "yes yes |" in front of snapshot/template-uninstall| #
# |                 so that deletion is confirmed without interactive and   | #
# |                 without using "force=true"                              | #
# | 2014_03_04 :                                                            | #
# |             1. Corrected functions that remove extraneous (older)       | #
# |                 backups                                                 | #
# |             2. Corrected functions that estimate free space left on sr  | #
# |                 or mountpoint                                           | #
# |             3. Updated function that gets SR to be used for template    | #
# |                 storage                                                 | #
# |             4. Added removal of zero-length files to workspace          | #
# |                 initialisation function. Protects from losing older but | #
# |                 valid backups to empty newer ones.                      | #
# | 2014_03_09 :                                                            | #
# |             1. Corrected functions that remove extraneous (older)       | #
# |                 backups, the part about templates in particular.        | #
# |                 Problem was caused by the fact that sorting was done    | #
# |                 for the list returned not by creation date but by uuid  | #
# |                 alphanumeric precedence.                                | #
# |-------------------------------------------------------------------------| #
# | VERSION # 0.3                                                           | #
# |                                                                         | #
# | COPYLEFT : Pattern Recognition Laboratory,                              | #
# |            Computer Engineering and Informatics Department              | #
# |            University of Patras                                         | #
# |                                                                         | #
# | DISCLAIMER: This software is provided as-is. Use at your own risk. The  | #
# |             author, distributor(s) and copyleft owners are not liable   | #
# |             for any loss of profit, business, data, time or any other   | #
# |             loss that may be caused by use of this software or any of   | #
# |             its derivatives.                                            | #
# |                                                                         | #
# | LICENCING : This software is provided under the terms and conditions of | #
# |             the GPLv3 license.                                          | #
# |-------------------------------------------------------------------------| #


#+ ============================================================================
#+ TODO's - Design notes
#+ =====================
#+ - Make variables editable via cmd line. Use 
#+      VARIABLE=${VARIABLE:-<default value>} method.
#+ - Add a TRAP exit to ensure cleanup after running the script. Among others 
#+      it should remove tempfiles, lockfiles and incomplete files.
#+ - Create function that decides, given parameters, if a VM should be 
#+      backed-up. The function should return a boolean value and should 
#+      consider:
#+        a. If any backups of the VM already exist (if not backup VM)
#+        b. If Any of the prerequisites to backup the VM exist.
#+        c. A default policy for unmarked VMs. (It should also notify upon 
#+            finding one).
#+      This function can handle the similar code used for TEMPLATE and XVA
#+      backup decisions.
#+ - Move certain functionality that is hardwired into functions. If functions
#+      aren't strictly required, then better comment - visually separate the
#+      code.  Especially so, do it for functions that remove items and
#+      functions that generate items, which have similar functionality.
#+ - Add logging functionality to script. Output should be redirected to proper
#+      file in /var/log directory. Add more verbosity in logs, such as 
#+      VM / Snapshot names and so on.
#+ - The script uses 'else' instead of 'elif' in most places. 'else' should be
#+      used to perform error-checking rather than assuming the default has 
#+      occured.
#+ - (OPTIONAL) expand timestamp to include 24format HR and MIN in order to
#+      make it more unique.
#+ x Should mktemp be used to create "safe" names for the backups as well? As
#+      in a name template that contains a 6 letter UUID as part of it?
#+ - Consider what policy should be followed when handling VM names when 
#+      exporting to file.
#+ - Use snapshot-uninstall or snapshot-destroy to remove snapshots?
#+ - VMs should be halted / restarted if backup_live is false. Not done yet.
#+ x VMs to template and VMs to xva correspondance required? Or at least
#+      VMs to uuids?
#+ ? (OPTIONAL) set return codes according to ERRNO?
#+ - Add function to remove surplus templates - xva files that are more in
#+      number than the backlog.
#+ - Modify storage repository of templates based on user choice.
#+ - Add copyright notice.
#+ - If weekly backup fails midway, then there will be duplicates. This should
#+      be handled correctly. For now, it is assumed that the backup procedure
#+      does not fail.
#+ - Add sr-rescan every so often to ensure that freed space is detected.
#+ - Add frequent free space checks to confirm that a limit is not being
#+      approached.
#+ * Add notify function that takes direct action to alert the system
#+      administrator in case such an emergency presents itself.
#+ - Make a backup of the db metadata as well.
#+ - Where should the sr of the template be defined? Should it be on a per VM
#+      basis or on a global basis?
#+ - Space checking function operates on an SR premise. In fact, the NFS is 
#+      mounted as a regular volume. Therefore, it should be checked as a 
#+      regular volume.

#+ ============================================================================
#+ General description
#+ ===================
#+      Get parameters
#+      Display and log start time
#+      Get VM list
#+      For each vm:
#+          get how it should be backed-up (none, xva, template) and how often
#+              it should be backed up. Eg. (xva-template, 1, 2) for something
#+              that requires both types and should keep on xva, two templates
#+              or (template, 0, 1) for something that should be backed-up only
#+              as a template (this time) and there should be 0 xva one template
#+              backups.
#+          run function to back it up for each type of backup.
#+          run function to clean extraneous xvas
#+          run function to clean extraneous templates
#+      Backup pool metatadata.
#+      End (exit function will be handled after trap)

#+ ============================================================================
#+ Programming shorthands used explained
#+ =====================================
#+  1. The following one-liner replaces the command-line arguments passed to the 
#+      function with an expression that, when evaluated locally, produces the 
#+      desired assignments. The way it works is that the expression 
#+          . <filename>
#+      sources a file, while 
#+          <(cmds) 
#+      provides a virtual file with contents the results of the execution of
#+      command. The reason this schema was used is that it allows overriding
#+      problems wit locality of variables in bash.



  #
### -- Variables
#
    # Non user-modifiable variables:
    start_time=$(date +%Y%m%d%H%M);
    full_date=$(date +%Y%m%d);
    today=$(date +%a);
    today_num=$(date +%d);
    day_num=$(date +%d);
    sync_retries="5";
    monthly_backup_today="0";
    weekly_backup_today="0";
    pool_uuid=$(xe pool-list --minimal)

    # Variables that are set / read from a temp file, so that they persist
    #+ when set by functions. They are used by cleanup_at_exit to sanitize
    #+ the workspace.
    globals=(                     \
        "snapshot_to_destroy:"    \
        "vm_to_start:"            \
        "unmount_nfs:1"           \
        "partial_file_to_remove:"); # /globals
    # The file used as intermediate storage for the global variables.
    globals_file=$(mktemp /tmp/globals.XXXXXXX);



    # User-modifiable variables:
    # USER_MODIFIABLE_OPTION is used for a script function and denotes a user (caller) modifiable variable.
    nfs_mount="${NFS_MOUNT:-150.140.139.93:/export}"; # USER_MODIFIABLE_OPTION
    nfs_mountpoint="${NFS_MOUNTPOINT:-/mnt}"; # USER_MODIFIABLE_OPTION
    lockfile="${LOCKFILE_PATH:-/var/run/lockfile.xen_backup}"; # USER_MODIFIABLE_OPTION
    log_filename="${LOG_FILENAME:-${start_time}.${pool_uuid}.xenserver_autobackup.log}"; # USER_MODIFIABLE_OPTION
    log_save_dir="${LOG_SAVE_DIR:-logs}"; # USER_MODIFIABLE_OPTION
    log_full_dir_path="${LOG_FULL_DIR_PATH:-${nfs_mountpoint}/${log_save_dir}}"; # USER_MODIFIABLE_OPTION
    log_full_file_path="${LOG_FULL_PATH:-${log_full_dir_path}/${log_filename}}"; # USER_MODIFIABLE_OPTION
    xva_backup_dir="${XVA_BACKUP_DIR:-backup}"; # USER_MODIFIABLE_OPTION
    xva_storage_path="${XVA_STORAGE_PATH:-${nfs_mountpoint}/${xva_backup_dir}}"; # USER_MODIFIABLE_OPTION
    xva_suffix="${XVA_SUFFIX:-bak}"; # USER_MODIFIABLE_OPTION
    monthly_on="${MONTHLY_ON:-Sat}"; # USER_MODIFIABLE_OPTION
    weekly_on="${WEEKLY_ON:-Sat}"; # USER_MODIFIABLE_OPTION
    template_storage="${TEMPLATE_STORAGE:-local}"; # USER_MODIFIABLE_OPTION
    snapshot_prefix="${SNAPSHOT_PREFIX:-temp}"; # USER_MODIFIABLE_OPTION
    snapshot_suffix="${SNAPSHOT_SUFFIX:-snapbak}"; # USER_MODIFIABLE_OPTION
    backup_only_live="${BACKUP_ONLY_LIVE:-0}"; # USER_MODIFIABLE_OPTION
    low_space_soft_limit="${LOW_SPACE_SOFT_LIMIT:-$((200 * (1024**3)))}"; # USER_MODIFIABLE_OPTION
    low_space_hard_limit="${LOW_SPACE_HARD_LIMIT:-$((50 * (1024**3)))}"; # USER_MODIFIABLE_OPTION
    rescan_limit="${RESCAN_LIMIT:-3}" # USER_MODIFIABLE_OPTION
    # Default values for backup settings. Conservative approach 
    default_backup_type="${BACKUP_TYPE:-xva-template}"; # USER_MODIFIABLE_OPTION
    default_xva_backup_freq="${XVA_BACKUP_FREQ:-weekly}"; # USER_MODIFIABLE_OPTION
    default_template_backup_freq="${TEMPLATE_BACKUP_FREQ:-weekly}"; # USER_MODIFIABLE_OPTION
    default_backup_live="${BACKUP_LIVE:-1}"; # USER_MODIFIABLE_OPTION
    default_xva_backlog="${XVA_BACKLOG:-1}"; # USER_MODIFIABLE_OPTION
    default_template_backlog="${TEMPLATE_BACKLOG:-1}"; # USER_MODIFIABLE_OPTION
    default_template_sr="${TEMPLATE_SR:-local}"; # USER_MODIFIABLE_OPTION
    # Below not user modifiable (yet?) because it is dependant on function
    #+ 'create_xva_backup' implementation
    xva_filename_format="\${xva_storage_path}/\${l_vm_uuid}.\${start_time}.xva"; 

    # Activate montly / weekly here, so that it can be edited more easily if needed.
    if [ "${today}" == "${weekly_on}" ] ; then
        weekly_backup_today="1";
    fi #/ if today is the day for weekly backups.
    if [ "${today}" == "${monthly_on}" -a 7 -ge "${day_num}" ] ; then
        monthly_backup_today="1";
    fi #/ if today is the day for monthly backups.

  #
### -- Functions
#
    function usage_instructions(){
        # Prints a help message explaining how this function works.
        # Required arguments: None
        # Optional arguments: None
        cat <<SCRIPTUSAGEINSTRUCTIONS | sed -e "s/^           //" 1>&2
            ${0}
            This bash scrint is meant to be used as a cron task. It can also be called as any bash script from the command line. It requires no arguments, because it has default behavior, but if desired said behavior can be altered by setting and exporting any of these environment variables:
            NFS_MOUNT           : The nfs share that is to be mounted.
              default: 150.140.139.93:/export
            NFS_MOUNTPOINT      : Sets the mountpoint where the nfs share should be attached.
              default: /mnt
            LOCKFILE_PATH       : Sets the full path for the lockfile to be used.
              default: /var/run/lockfile.xen_backup
            LOG_FILENAME        : The file name used for the log file
              default: <start_time>.xenserver_autobackup_log
            LOG_SAVE_DIR        : The (relevant) path for the logs.
              default: logs
            LOG_FULL_DIR_PATH   : The full directory path for the log. Setting this overrides LOG_SAVE_DIR
              default: <nfs_mountpoint>/<log_save_dir>
            LOG_FULL_FILE_PATH  : The full path for the log. Setting this overrides LOG_SAVE_DIR, LOG_FILENAME and LOG_FULL_DIR_PATH
              default: <log_full_dir_path>/<log_filename>
            XVA_BACKUP_DIR      : The directory (relevant path) in which the xva backups will be kept.
              default: backup
            XVA_STORAGE_PATH    : The full path of the directory xva files are stored. Setting this overrides XVA_BACKUP_DIR
              default: <nfs_mountpoint}/<xva_backup_dir>
            XVA_SUFFIX          : The suffix just before .xva for xva backups. 
              default: bak
            MONTHLY_ON          : Day of the month monthly backups should be taken on.  Holds for first occurence of day in month.
              default: Saturday (Sat)
            WEEKLY_ON           : Day of the week weekly backups are taken on.
              default: Saturday (Sat)
            TEMPLATE_STORAGE    : The sr type to be used.
                                    local       -> Use local storage
                                    nfs         -> Use NFS SR
              default: local
            SNAPSHOT_PREFIX     : A prefix for the temporary snapshots (i.e. not the templates) taken to facilitate safer copying.
              default: temp
            SNAPSHOT_SUFFIX     : The suffix used in snapshot names to indicate that snapshot was taken for backup purposes.
              default: snapback
            BACKUP_ONLY_LIVE    : Boolean whether only running VMs should be backed-up.
              default: 0
            LOW_SPACE_SOFT_LIMIT: Numeric, the soft limit for the free space on all SRs
              default: 200 GB
            LOW_SPACE_HARD_LIMIT: Numeric, the hard limit for the free space on all SRs
              default: 50 GB
            RESCAN_LIMIT        : How many VMs should be edited before the SRs are re-scanned.
              default: 3
            BACKUP_TYPE         : The backup type for this machine. Allowed values are
                                    template     -> Only template backup.
                                    xva          -> Only xva backup
                                    xva-template -> Both xva and template backups
                                    never        -> Do not backup (for test VMs)
              default: xva-template
            XVA_BACKUP_FREQ     : Indicates frequency for taking of xva backups. Allowed
                                    values are daily, weekly, monthly and never
              default: weekly
            TEMPLATE_BACKUP_FREQ: Indicates frequency for taking of template backups.  Allowed values as for xva backup.
              default: weekly
            BACKUP_LIVE         : Indicates wheter the machine should be kept running while a backup is taking place. 
              default: true
            XVA_BACKLOG         : How many xva backups should be kept.
              default: 1
            TEMPLATE_BACKLOG    : How many template backups should be kept.
              default: 1
            TEMPLATE_SR         : Default value for backup parameters. What SR should be preferred.
                                    local       -> local storage
                                    nfs         -> nfs storage
                                    default     -> script default
              default: default.
SCRIPTUSAGEINSTRUCTIONS
    } # function usage_instructions


    



    function rescan_sr(){
        # Rescans all srs so that their information is updated after creating /
        #+ deleting VM backups.
        # Required arguments: None.
        # Optional arguments: None
        local l_sr_list=( $( xe sr-list --minimal | \
            sed -e "s/,/ /g" )); 
        for i in ${l_sr_list[@]}; do
            xe sr-scan uuid="${i}"
        done # /for all all srs
    } # / function rescan_sr




    function backup_db_metadata(){
        # Creates a backup of the db metadata, including vm-to-uuid correlations.
        # Required arguments: None
        # Optional arguments: None
        # Get IP of pool master.
        local l_pool_ips="";
        local l_current_ip=();
        local l_pif=$( xe pif-list --minimal | sed -e "s/,/ /g" );
        for i in ${l_pif[@]}; do
            l_current_ip=( ${l_current_ip[@]} $( xe pif-param-get uuid=${i} param-name=IP | \
                sed -e "s/\./_/g") )
        done # /for all pifs
        l_pool_ips=$( echo "${l_current_ip[@]}"  | \
            sed -e "s/ /-/g" )

        if [ -z "${l_pool_ips}" ];then
            log ERROR "Couldn't get any IPs for the pool."
            return 1;
        fi #/ if pool physical IPs all blank.
        
        # Create pool-to-vm correspondence file. Store in logs.
        xe vm-list > "${log_full_dir_path}/${l_pool_ips}.${full_date}.vm_to_uuid.log"

        # Backup db metadata. Store in xva storage path.
        xe pool-dump-database file-name="${xva_storage_path}/${l_pool_ips}.${full_date}.pool_db_dump.bak"
        return 0;
    } # / backup_db_metadata



    function get_value_in_range(){
        # Issues a warning depending on where free space lies. 
        #+ It could be used to pause operation if hard limit is reached.
        # Required arguments: Positional:
        #+  soft_limit
        #+  hard_limit
        #+  value
        # Optional arguments: Positional:
        #+ previous_state Previous worst case scenario.
        local l_soft_limit=${1};
        local l_hard_limit=${2};
        local l_value=${3};
        local l_previous_worst=${4};
        local l_nocasematch=$(shopt -p nocasematch);
        if [ "${l_hard_limit}" -gt "${l_soft_limit}" ]; then
            log WARNING "Hard limit set higher than soft."
            eval "${l_nocasematch}";
            return 1;
        fi

        if [ "hard" == "${l_previous_worst}" ]; then
            echo "hard";
            eval "${l_nocasematch}";
            return 0;
        fi # /if prefious was hard.

        if [ "${l_value}" -lt "${l_hard_limit}" ];then
            echo "hard";
        # / if hard case.
        elif [ "${l_value}" -lt "${l_soft_limit}" ];then
            echo "soft";
        # /if soft case.
        else 
            if [ "soft" == "${l_previous_worst}" ]; then
                echo "soft";
            else
                echo "fine";
            fi #/if this is fine, previous was soft.
        fi #/if value within ranges.

        eval "${l_nocasematch}";
        return 0;
    } #/get_value_in_range



    function get_sr_free_space(){
        # Calculates the free space on the SR
        # Required arguments: Positional:
        #+  SR UUID
        # Optional arguments: None
        local l_sr_to_probe="${1}";
        
        # The mountpoint is expected to be given as absolute path.
        if { echo "${l_sr_to_probe}" | grep -q -e "/" ; }; then
            available_space=$(df --sync -k -P "${l_sr_to_probe}"    | \
                sed -e 's/[ \t]\+/ /g'                              | \
                cut -d ' ' -f 4                                     | \
                tail -n -1                                          );
            echo $((available_space * 1024 ));
        else
            total_space=$(xe sr-param-get       \
                uuid="${l_sr_to_probe}"         \
                param-name=physical-size        );
            used_space=$(xe sr-param-get        \
                uuid="${l_sr_to_probe}"         \
                param-name=physical-utilisation );
            echo $((total_space - used_space));
        fi # /if sr is uuid or mountpoint.
        return 0;
    } # /get_sr_free_space


    function get_free_space_state(){
        # Issues a warning depending on where free space lies. 
        #+ It could be used to pause operation if hard limit is reached.
        # Required arguments: None
        # Optional arguments: Positional:
        #+ SR uuid OR
        #+ mount point (directory absolute path)
        # TODO add a way to check based on TYPE of repository.
        local l_sr_to_probe="${1}";
        local l_status="0";

        # Only call xe sr-scan if it's not a path.
        if [ ! -z "${l_sr_to_probe}" ] ;then
            echo "${l_sr_to_probe}" | \
                grep -q -e ".*/.*"
            if [ "0" -ne "$?" ]; then
                xe sr-scan uuid="${l_sr_to_probe}";
            fi # /if not path
            local l_free_space=$(get_sr_free_space "${l_sr_to_probe}");
            local l_free_space_state=$(get_value_in_range   \
                "${low_space_soft_limit}"                   \
                "${low_space_hard_limit}"                   \
                "${l_free_space}"                     );
        else
            local l_sr_list=( $({ xe sr-list type=nfs --minimal; \
                xe sr-list --minimal type=ext ;} | \
                sed -e "s/,/ /g") ${nfs_mountpoint} );
            for l_sr_to_probe in ${l_sr_list[@]}; do
                # This is necessary because otherwise space released is not recognised.
                xe sr-scan uuid="${l_sr_to_probe}";
                l_free_space=$(get_sr_free_space "${l_sr_to_probe}");
                l_free_space_state=$(get_value_in_range \
                    "${low_space_soft_limit}"           \
                    "${low_space_hard_limit}"           \
                    "${l_free_space}"                   \
                    ${l_free_space_state}               );
                if [ "0" -ne "$?" ] ;then
                    echo "hard";
                    log ERROR "Something went wrong while calculating free space. Consider worst-case scenario."
                    return 1;
                fi
            done # /for all SRs
        fi
        echo "${l_free_space_state}";
        return 0;
    } # / get_free_space_state



    function notify_sysadmin(){
        # Sends an e-mail to the system administrator when things have gone horribly wrong.
        #+ Sysadmin should have been checking logs, but that's never guaranteed...
        # Required arguments: Positional:
        #+  Message to be sent
        # Optional arguments: None
        # FIXME IMPLEMENT
        # Empty for now
        return 0;
    } # / notify_sysadmin




    function get_template_sr(){
        # Gets the uuid of the sr to be used for template storage.
        # Required arguments: Positional:
        #+  type of sr required.
        #+  vm_uuid the sr is about
        # Optional arguments: None
        # FIXME : The only "important" value for the type is nfs
        #+          everything else is ingored. 
        local nocasematch_status=$(shopt -p nocasematch);
        local l_sr_type=${1};
        local l_vm_uuid=${2};
        local l_storage_uuid="";
        local l_status="0";

    # Below selects the most relevant, safe sr to use
        if [ "nfs" == "${l_sr_type}" ] ;then
                log INFO "Selecting nfs sr as template default storage";
                l_storage_uuid=( $(                 \
                    xe sr-list --minimal type=nfs   | \
                    sed -e "s/,/\n/g"               )); 

        else
                log INFO "Selecting local sr as template default storage";
            # Get hosts that are available to the VM
            local l_possible_hosts=( $(xe vm-param-get  \
                param-name=possible-hosts               \
                uuid="${l_vm_uuid}"                     | \
                sed -e "s/;/ /g"                        ));
            # Get the name labels of the available hosts
            local l_host_name_labels=( $(\
                for i in ${l_possible_hosts[@]} ; do 
                    xe host-list uuid="${i}"            | \
                    grep -e name-label                  | \
                    cut -d ":" -f 2
                done                                    ));
            # Get the sr uuids available to the hosts.
            local l_storage_uuid=($(                   \
                for i in ${l_host_name_labels[@]} ; do 
                    xe sr-list --minimal                \
                        name-label="Local storage"      \
                        host="${i}"                     | \
                    sed -e "s/,/ /g"
                done                                    ));
        fi # /if nfs - local
            
        # If l_sr_uuids is empty, something went wrong. Report and exit.
        if [ "0" -eq "${#l_storage_uuid[@]}" ] ;then
            log ERROR "Could not find any ${l_sr_type} SRs that are relevant to this VM"
            return 1;
        fi

        # Now get the first sr from this list that hasn't reached
        #+ a hard limit.
        local l_sr_state="";
        for i in ${l_storage_uuid[@]};do
            l_sr_state=$(get_free_space_state ${i});
            if [ "hard" == "${l_sr_state}" ]; then
                log WARNING "SR ${i} has reached hard limit for capacity"
                notify_sysadmin "WARNING" "Hard limit reached for SR with uuid ${i}"
                continue;
            elif [ "soft" == "${l_sr_state}" ]; then
                log WARNING "SR ${i} has reached soft limit for capacity"
            else
                echo ${i};
                return 0;
            fi
        done
        return 1;
    } #/ get_template_sr



    function set_global(){
        # Set the values of global variables.
        #+ Uses an intermediate file to allow functions to modify and share values,
        #+ something bash does not regularly allow.
        # Required arguments: Mappings:
        #+  key:value pair for global variable.
        # Optional arguments: None
        local l_key_value_pair="${1}";
        local l_current_key_value_pair="";
        local l_key="";
        local l_value="";
        local l_default_value="";
        l_key=$(echo ${l_key_value_pair} | cut -d ":" -f 1);
        l_value=$(echo ${l_key_value_pair} | cut --complement -d ":" -f 1);

        echo "${l_key_value_pair}" | grep -q -e ":"
        if [ "0" -ne "$?" -o -z "${l_key}" ] ; then
            log ERROR "set_global not in format <key>:<value>. Instead: ${1}"
            return 1;
        fi # /if format not key:value. 
        
        l_default_value=$(for i in ${globals[@]}; do
                echo ${i};
            done | grep -e "^${l_key}:.*"
        ); # Find if variable is in the default values and get default value.
        if [ -z "${l_default_value}" ] ;then
            log ERROR "Attempting to set non-existing global ${l_key}";
            return 1;
        fi

        if [ ! -r "${globals_file}" ]; then
            log ERROR "Globals file does not exist or not readable.";
            return 1;
        fi # /if global file not present / not readable.

        l_current_key_value_pair=$(
            grep -e "^${l_key}:.*" "${globals_file}"
        ); #/ get current value in the file.

        if [ -z "${l_current_key_value_pair}" ]; then # if value not yet in file - add.
            # sed does not insert in empty files, therefore this workaround is required.
            if [ "0" -eq "$(cat ${globals_file} | wc --bytes)" ] ; then
                echo "${l_key_value_pair}" >> "${globals_file}"
            else
                sed -i -e "1i${l_key_value_pair}" "${globals_file}";
            fi
        else # else value in file - replace
            sed -i -e "/^${l_key}:.*/c${l_key_value_pair}"  "${globals_file}";
        fi

        return 0;
    } # /function set_global


    function get_global(){
        # Get the values of global variable based on key.
        #+ Uses an intermediate file to allow functions to modify and share values,
        #+ something bash does not regularly allow.
        # Required arguments: Positional:
        #+  name of global variable.
        # Optional arguments: None
        local l_variable_name="${1}";
        local l_key_value_pair="";
        local l_key="";
        local l_value="";
        local l_default_value="";

        # Check that the variable name is in the list of recognised globals. If
        #+ so, keep it's default value.
        l_default_value=$(for i in ${globals[@]}; do
                echo ${i};
            done | grep -e "^${l_variable_name}:.*"
        ); # Find if variable is in the default values and get default value.

        if [ -z "${l_default_value}" ] ;then
            log ERROR "Requested non-existing global ${l_variable_name}";
            return 1;
        fi # /if default value is null.

        # If the value isn't found in the file, call set_global to set it first.
        l_key_value_pair=$( grep -e "${l_variable_name}:.*" ${globals_file} );
        if [ -z "${l_key_value_pair}" ] ;then
            set_global ${l_default_value} &&    \
                get_global ${l_variable_name};
            return $?
        fi

        l_key=$(echo ${l_key_value_pair} | cut -d ":" -f 1);
        l_value=$(echo ${l_key_value_pair} | cut --complement -d ":" -f 1);
        echo "${l_value}";
        return 0;
    } # /function get_global
    


    function log(){
        # Saves the Message in the log file and prints it on stderr as well.
        # Required arguments: Message
        # Optional arguments: None
        # TODO  A future optional argument could indicate the level at which
        #+      each comment should be added. This way loglevels could be
        #+      implemented.
        if [ "DEBUG" == "${1}" ]; then
            if [ -z "${DEBUG}" ]; then
                 return 0;
            fi # /if DEBUG not set
            if [  "1" -ne "${DEBUG}" ]; then
                return 0;
            fi # /if DEBUG not set to 1. 
        fi # /if debug message without active debug.
        echo -e "[$(date +%Y%m%d' - '%H:%M:%S)]\t${FUNCNAME[1]}\t${1}\t${@:2}" | \
            tee -a "${log_full_file_path}" 1>&2
        return 0;
    } # /function log



    function get_all_vm_uuids(){
        # Returns the uuids of all the vms on the server 
        # Required arguments: None
        # Optional arguments: None
        # TODO a list of optional arguments to indicate vm characteristics
        # to get the list of.
        xe vm-list --minimal is-control-domain=false | \
            sed -e "s/,/ /g";
        return $?
    } # function get_all_vm_uuids





    function pick_from_list(){
        # Reads input from stdin and matches it against the list of its args.
        #+ returns only when successfully matched.
        # Required arguments: list of valid inputs. 
        #   For numbers the arguments allowed are:
        #       <integer>       (any int)
        #       <posinteger>    (int > 0)
        #       <posorzero>     (int >=0)
        while true; do # Infinite loop, return when valid input
            unset REPLY;
            if [ "<posinteger>" ==  "${1}" ]; then
                echo -n "Please give a positive integer ( >0): " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                if [ "0" -ge "${REPLY}" ]; then
                    echo "Invalid input, please try again."  1>&2
                    continue;
                fi # / if value within range.
                echo ${REPLY};
                return 0;
            elif [ "<posorzero>" ==  "${1}" ]; then
                echo -n "Please give a positive integer ( >=0): " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                if [ "0" -gt "${REPLY}" ]; then
                    echo "Invalid input, please try again."  1>&2
                    continue;
                fi # / if value within range.
                echo ${REPLY}
                return $?
            elif [ '<integer>' ==  "${1}" ]; then
                echo -n "Please give an integer: " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                # TODO does not handle negatives. (Not necessary so far)
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                echo ${REPLY}
                return $?
            else
                count=1;
                for i in ${@}; do
                    echo "$((count++)). ${i}" 1>&2;
                done ; # /for i in all args.
                echo -n "Please select the *list number* of one of the " 1>&2
                echo -n "above options: " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    echo "";
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                elif [ "0" -lt "${REPLY}" -a "${REPLY}" -le "$#" ]; then
                    # FIXME this part is "dangerous". What it does is replace the
                    #+ value of Reply with an actual number and pass that to eval 
                    #+ to echo the corresponding cmdline argument.
                    eval echo \${$REPLY};
                    return 0;
                else
                    echo "Value out-of-range. Please try again." 1>&2
                    continue;
                fi # /if selection numeric and within range.
            fi  # /if numbers or list
        done
    } ; # / function pick_from_list



    function set_vm_backup_parameters(){
        # sets the vm_backup_parameters, automatically after user choice
        #+ or timeout, or by reading user choice.
        # Required arguments: Positional:
        #+  uuid of vm
        # Optional arguments: None

        local vm_uuid="${1}";
        log INFO "VM ${vm_uuid} has not been setup for backup"
        local interactive="n";
        local l_backup_type="";
        local l_xva_backup_freq="";
        local l_template_backup_freq="";
        local l_backup_live="";
        local l_xva_backlog="";
        local l_template_backlog="";
        local l_template_sr="";

        # set bash nocasematch to true, after preserving current state.
        #+ revert to current state before returning.
        local nocasematch_status=$(shopt -p nocasematch)
            shopt -s nocasematch


            echo -n "Would you like to manually setup VM for backup? [y/N]: " 1>&2
            read -t 20 interactive;
            if [ "y" == "${interactive}" -o "yes" == "${interactive}" ]; then
                log INFO "Setting VM backup settings for ${vm_uuid} interactively" 
                echo "Backup type" 1>&2;
                l_backup_type="$(pick_from_list template xva xva-template never)";
                echo "XVA backup frequency" 1>&2;
                l_xva_backup_freq="$(pick_from_list daily weekly monthly never)";
                echo "Template backup frequency" 1>&2;
                l_template_backup_freq="$(pick_from_list daily weekly monthly never)";
                echo "Backup live" 1>&2;
                l_backup_live="$(pick_from_list true false)";
                echo "XVA backlog" 1>&2;
                l_xva_backlog="$(pick_from_list \<posorzero\>)";
                echo "Template backlog" 1>&2;
                l_template_backlog="$(pick_from_list \<posorzero\>)";
                echo "Template SR" 1>&2;
                l_template_sr="$(pick_from_list local nfs default)";
                local l_status="1";
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.backup_type=${l_backup_type}                    && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.xva_backup_freq=${l_xva_backup_freq}            && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_backup_freq=${l_template_backup_freq}  && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.backup_live=${l_backup_live}                    && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.xva_backlog=${l_xva_backlog}                    && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_backlog=${l_template_backlog}          && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_sr=${l_template_sr}                    && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.has_backup_params=1                             && \
                l_status="0";
                eval "${nocasematch_status}";
                return "${l_status}";
            else
                if [ -z "${interactive}"       -o \
                     "no" == "${interactive}"  -o \
                     "n" == "${interactive}" ]; then

                     # If no input, add a blank line.
                     [ -z "${interactive}" ] && echo "";
                     log INFO "Automatically setting VM backup parameters for ${vm_uuid} to defaults"
                else
                     log WARNING "Invalid input given: ${interactive}. Using defaults"
                fi # / if valid input - else report error

                # Use default settings.
                log INFO "Using default backup settings for VM ${vm_uuid}:";
                log DEBUG "default_backup_type:${default_backup_type}"
                log DEBUG "default_xva_backup_freq:${default_xva_backup_freq}"
                log DEBUG "default_template_backup_freq:${default_template_backup_freq}"
                log DEBUG "default_backup_live:${default_backup_live}"
                log DEBUG "default_xva_backlog:${default_xva_backlog}"
                log DEBUG "default_template_backlog:${default_template_backlog}"
                log DEBUG "default_template_sr:${default_template_sr}"
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.backup_type=${default_backup_type}                      && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.xva_backup_freq=${default_xva_backup_freq}              && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_backup_freq=${default_template_backup_freq}    && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.backup_live=${default_backup_live}                      && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.xva_backlog=${default_xva_backlog}                      && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_backlog=${default_template_backlog}            && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.template_sr=${default_template_sr}                      && \
                xe vm-param-set uuid=${vm_uuid} other-config:XenCenter.CustomFields.has_backup_params=1                                     && \
                l_status=0;
                eval "${nocasematch_status}";
                return "${l_status}";
            fi # / if interactive - else non-interactive
            # Control should NEVER reach this part. If it does, log and return error.
            log ERROR "Unexpected problem in set_vm_backup_parameters.";
            eval "${nocasematch_status}";
            return "${l_status}";
        } # /function set_vm_backup_parameters



            
        function get_value_by_key(){
            # Helper function that gets other-config values based on key.
            # Required arguments: Positional:
            #+  vm-uuid
            #+  key name
            # Optional arguments: None
            xe vm-param-get                             \
                uuid="${1}"                             \
                param-name=other-config                 \
                param-key="XenCenter.CustomFields.${2}" ;
            return $?
        } # /get_value_by_key


        function get_vm_backup_parameters(){
            # Prints on stdout the vm backup parameters in a way that bash can parse.
            #+ The output of this function can then be sourced directly into the script.
            # Required arguments: Positional:
            #   uuid of vm
            # Optional arguments: None
            local l_vm_uuid=${1};
            local l_params_are_set="";
            local l_param_value="";
            # Below duplicates code from get_value_by_key because it silently discards errors.
            l_params_are_set=$(xe vm-param-get uuid=${l_vm_uuid}               \
                param-name=other-config                                        \
                param-key=XenCenter.CustomFields.has_backup_params 2>/dev/null);
            local l_status="$?"
            if [ -z "${l_params_are_set}" ] ; then
                l_params_are_set="0";
            fi
            if [ "0"  -ne "${l_status}" -o "1" -ne "${l_params_are_set}" ] ;then
                set_vm_backup_parameters ${l_vm_uuid} && \
                    get_vm_backup_parameters ${l_vm_uuid};
                return $? ;
            fi # /if something went wrong while getting the parameters.

            for i in \
                "backup_type"           \
                "xva_backup_freq"       \
                "template_backup_freq"  \
                "backup_live"           \
                "xva_backlog"           \
                "template_backlog"      \
                "template_sr"           ; do
                l_param_value=$(get_value_by_key ${l_vm_uuid} ${i})

                if [ -z "${l_param_value}" ] ;then 
                    if [ "template_sr" != "${i}" ]; then
                        log ERROR "VM ${l_vm_uuid} does not have parameter ${i} set."
                        eval "l_param_value=\${default_${i}}";
                    fi #/ if the unset value is not template_sr then set to default and warn
                      
                elif  [ 'default' == "${l_param_value}" ]; then
                    log INFO "VM ${l_vm_uuid} parameter ${i} set to 'default'"
                    eval "l_param_value=\${default_${i}}";
                fi ; #/ if parameter blank or 'default'

                echo "${i}=${l_param_value}";
            done ; # /for each key.

        } # /function get_vm_backup_parameters




        function get_vm_has_backups(){
            # Returns 0 if at least one backup of given type exists for the
            #+ VM.
            # Required arguments: Positional:
                # vm_uuid               : valid uuid
                # check_for             : xva, template
            # Optional arguments: None
            if [ "template" == "${2}" ]; then
                xe template-list                                              \
                    other-config:XenCenter.CustomFields.template-of="${1}"  | \
                        grep -q -e "^.\+$"                                  ;
                return $?
            elif [ "xva" == "${2}" ]; then
               # Perform ls in directory of backups and grep with VM UUID
               #+ !!! IMPORTANT !!! Assumes VM UUID is part of filename.
               #+ This assumption is rational and good practice should follow.
                ls -1 "${xva_storage_path}"  | \
                    grep -q -e "${1}"        ;
                return $?
            else
                log WARNING "get_vm_has_backups called with peculiar type: ${2}"
                return 0; # Return success to avoid activating backup.
            fi
        } #/ function get_vm_has_backups




        function get_if_should_backup(){
            # Returns 0 if the VM should be backed-up, taking constraints into
            #+ consideration.
            # Required arguments: Maps of:
                # vm_uuid               : valid uuid
                # backup_type           : xva, template, xva-template, never
                # check_for             : xva, template
            # Mutually exclusive arguments: Maps of:
                # xva_backup_freq       : daily, weekly, monthly, never
                # template_backup_freq  : daily, weekly, monthly, never
            # Optional arguments: None
            # Sample call:
            # get_if_should_backup "vm_uuid:${l_vm_uuid}"                         \
            #                      "backup_type:${l_backup_type}"                 \
            #                      "check_for:template"                           \
            #                      "template_backup_freq:${template_backup_freq}";

            # The following one-liner replaces the command-line arguments
            #+ passed to the function with an expression that, when evaluated
            #+ locally, produces the desired assignments.
            for i in $(for i in $*; do echo "l_${i}" | sed -e "s/:/=/"; done); do
                eval local $i;
            done
            
            local l_backup_freq="";
            local backedup_today="0";

            if [[ "${l_check_for}"  == template ]] ; then
                l_backup_freq="${l_template_backup_freq}"
                # Check if there is a template from today already.
                backedup_today=$(xe template-list                                   \
                    "other-config:XenCenter.CustomFields.template-of=${l_vm_uuid}"  \
                    "other-config:XenCenter.CustomFields.created-on=${full_date}"   | \
                    wc -l );
            elif [[ "${l_check_for}"  == xva ]] ; then
                l_backup_freq="${l_xva_backup_freq}"
                # Check if there is a file from today already.
                backedup_today=$(find "${xva_storage_path}" \
                    -name "*${l_vm_uuid}*" 2>/dev/null      | \
                    grep -e "${full_date}"                  | \
                    wc -l);
            else
                log ERROR "Unknown backup type: ${l_check_for}"
                return 1;
            fi

            if [ "never" == "${l_backup_type}" ] ;then
                log INFO "VM ${l_vm_uuid} has backup frequency set to 'never'"
                return 1;
            fi # /if backup_type is never.
            
            if [ "0" -ne "${backedup_today}" ]; then
                return 1;
            fi # /if there is a backup from today.

            #if [[ "${l_check_for}" != ** ]] ; then
            if ! ( echo "${l_backup_type}" | grep -q -e "${l_check_for}" ) ; then
                log INFO "VM ${l_vm_uuid} does not require ${l_check_for} type backups."
                return 1;
            fi # /if backup_type is asymphonous with type being checked for.

          

            # TODO Backup type may be set with frequency set to never. 
            #+ There is no check for this as of yet because it is something that
            #+ should not occur and is thus treated as not occuring.

            if [ "daily" == "${l_backup_freq}" ] ;then
                return 0;
                # Check if VM schedule is set to daily. If so, a backup should be taken.
            fi

            get_vm_has_backups      \
                "${l_vm_uuid}"      \
                "${l_check_for}" ; 
            if [ "0" -ne "$?" ] ;then
                # Check if there are any backups of the VM as of yet. If not
                #+ one should be taken out of turn.
                log INFO "VM with uuid ${l_vm_uuid} has no backups. Create one.";
                return 0;
            fi
            
            # If weekly / monthly, see if it's the appropriate time.
            if [ "weekly" == "${l_backup_freq}" ] ; then
                if [ "1" -eq "${weekly_backup_today}" ] ; then
                    return 0;
                else
                    return 1;
                fi
            elif [ "monthly" == "${l_backup_freq}" ]; then
                if [ "1" -eq "${monthly_backup_today}" ] ; then
                    return 0;
                else
                    return 1;
                fi
            else 
                # Something went wrong. Log.
                log WARNING "Unknown ${l_check_for}  backup frequency for VM ${l_vm_uuid}: ${l_backup_freq}."
                return 1;
            fi
            log ERROR "Unexpectate case occured in ${l_vm_uuid}"
            return 1;
        } # function get_if_should_backup





        function retain_latest_n_backups(){
            # Deletes all but the n latest backups
            # Required arguments: Maps of:
                # vm_uuid           : valid uuid
                # backup_type       : xva, template
                # preserve_n        : positive integer.
            # Optional arguments: None
            # The following one-liner replaces the command-line arguments
            #+ passed to the function with an expression that, when evaluated
            #+ locally, produces the desired assignments.
            for i in $(for i in $*; do echo "l_${i}" | sed -e "s/:/=/"; done); do
                log DEBUG "evaluating $i"
                eval local $i;
            done

            if [ "template" == "${l_backup_type}" ] ; then
                # Get all backups that are template-of and ignore the n latest.
                # This is more complex than the xva counterpart because sorting is
			    #+ based on alphanumeric precedence of uuid, not creation date.
				all_vm_templates=( $(													\
                    xe template-list --minimal                                          \
                        other-config:XenCenter.CustomFields.template-of="${l_vm_uuid}"  | \
					sed -e 's/,/\n/g'													));
                log DEBUG "All VM templates for ${l_vm_uuid}: ${all_vm_templates[@]}"

                older_template_uuids=($( for template_uuid in ${all_vm_templates[@]} ; do 
                        creation_date=$(xe template-param-get               \
                                uuid=${template_uuid}                       \
                                param-name=other-config                     \
                                param-key=XenCenter.CustomFields.created-on );
                        # Templates without creation dates are considered ancient
                        echo "${creation_date:-19000101} ${template_uuid}"; 
                    done                            | \
                    sort							| \
                    cut -d " " -f 2                 | \
                    head -n -${l_preserve_n:-9999}	)); #/ older_template_uuids
                log DEBUG "Older VM templates for ${l_vm_uuid}: ${older_template_uuids[@]}"

                for older_template in ${older_template_uuids[@]} ;do
                    log INFO "removing template with uuid = ${older_template}";
                    yes yes | xe template-uninstall template-uuid="${older_template}";
                    if [ "0" -ne "$?" ];then
                        log WARNING "Failed to remove template with uuid = ${older_template}";
                    fi # /if something went wrong
                done; # /for all older templates

            elif [ "xva" == "${l_backup_type}" ] ; then
                older_xva_files=( $(                      \
                    ls -1 "${xva_storage_path}"         | \
                        grep -e "${l_vm_uuid}"          | \
                        head -n -"${l_preserve_n:-9999}" ) );
                for i in ${older_xva_files[@]}; do
                    log INFO "Removing file ${i}";
                    rm -f "${xva_storage_path}/${i}";
                done
                # Get all files that are from this VM and ignore the n latest.
            else
                log ERROR "retain_latest_n_backups: unknown type of backup to retain: ${l_preserve_n}"
                return 1;
            fi

        } # /retain_latest_n_backups


        function get_should_stop_vm(){ # Checks if the VM can/should be stopped for the duration of the backup.
            #+ Gotcha: If the VM is stopped while it is being backed-up it will
            #+ be restarted.
            # Required arguments: Positional
                # vm_uuid               : valid uuid
            # Optional arguments: None
            local l_vm_uuid="${1}";
            xe vm-list uuid="${l_vm_uuid}" power-state=running | \
                grep -q -e "${l_vm_uuid}";
            machine_is_running="$?";
            if [ "0" -ne "${machine_is_running}" ];then
                # Machine is not running, no point in "stopping" it.
                return 1;
            fi

            local l_backup_live=$( get_value_by_key "${l_vm_uuid}" "backup_live" );
            if [ "0" -ne "$?" ]; then
                log ERROR "Unexpected error while trying to get backup_live value from VM ${l_vm_uuid}: ${l_backup_live}"
                return 1;
            fi

            # Test true / false status of backup live.
            if { echo ${l_backup_live} | \
                grep -ie yes -ie true -e 1; }; then
                log INFO "Will be backing-up VM ${l_vm_uuid} while online";
                return 1;
            elif { echo ${l_backup_live} | \
                grep -ie no -ie false -e 0; }; then
                log INFO "Will be stopping VM ${l_vm_uuid} for the duration of the backup.";
                return 0;
            else
                log WARNING "VM ${l_vm_uuid} has unexpected backup_live value: ${l_backup_live}";
                return 1;
            fi # /if yes / no /something unexpected
        # Check what the VM parameters are.
    } # /get_should_stop_vm





    function create_template_backup(){
        # Creates the template backup.
        # Required arguments: Maps of:
            # vm_uuid               : valid uuid
            # backup_type           : xva, template, xva-template, never
            # template_backup_freq  : daily, weekly, monthly, never
            # backup_live           : yes, 1, true, no, 0, false
            # template_backlog      : <positive integer or 0>
        # Optional arguments: None

        # The following one-liner replaces the command-line arguments
        #+ passed to the function with an expression that, when evaluated
        #+ locally, produces the desired assignments.
        for i in $(for i in $*; do echo "l_${i}" | sed -e "s/:/=/"; done); do
            eval local $i;
        done

        get_if_should_backup "vm_uuid:${l_vm_uuid}"                         \
                             "backup_type:${l_backup_type}"                 \
                             "check_for:template"                           \
                             "template_backup_freq:${l_template_backup_freq}";
        if [ 0 -ne "$?" ] ;then
            log INFO "Template backup not required for VM with uuid ${l_vm_uuid}."
            return 0;
        fi

        # Set the sr of preference for the SSID
        
        local l_template_sr_uuid="";

        if [ -z "${l_template_sr}" -o \
            "default" == "${l_template_sr}" ]; then
            log INFO "Using default SR for template of VM with UUID = ${l_vm_uuid}"
            l_template_sr_uuid=$(get_template_sr ${template_storage} ${l_vm_uuid} );
        elif [ "nfs" == "${l_template_sr}" -o \
               "local" == "${l_template_sr}" ] ;then
            log INFO "Using ${l_template_sr} SR for template of VM with UUID = ${l_vm_uuid}"
            l_template_sr_uuid=$(get_template_sr ${l_template_sr} ${l_vm_uuid});
        else 
            log ERROR "Invalid SR type '${l_template_sr}' SR for template of VM with UUID = ${l_vm_uuid}. Using default."
            l_template_sr_uuid=$(get_template_sr ${template_storage} ${l_vm_uuid} );
        fi # / if template_sr to be used is default.



        # Get the current name label. Using cut --complement removes only the 
        #+ 'name-label ( RW)' section, preserving the rest of the name,
        #+ including any ':' characters found within it.
        vm_name_label="$( xe vm-list uuid=${l_vm_uuid}      | \
                            grep -e 'name-label'            | \
                            cut --complement -d ':' -f 1    | \
                            sed -e 's/^[ \t]\+//')"

        # Get if vm should (can) be stopped for the backup.
        get_should_stop_vm "${l_vm_uuid}"; if [ "0" -eq "$?" ];then
            log INFO "Stopping VM ${l_vm_uuid} for the duration of the backup.";
            set_global "vm_to_start:${l_vm_uuid}";
            xe vm-shutdown vm="${l_vm_uuid}";
        fi # /test if VM should be stopped for the duration of the backup.

        # Create snapshot as safeguard for the backup. (This way if machine status changes
        #+ it does not affect the backup procedure. Stopping the VM simply speeds up the 
        #+ process.
        l_snapshot_uuid=$( \
            xe vm-snapshot vm="${l_vm_uuid}" \
                new-name-label="${snapshot_prefix}.${today}.${l_vm_uuid}.${snapshot_suffix}" )
        set_global "snapshot_to_destroy:${l_snapshot_uuid}";
        
        # Create the template from the snapshot.
        # snapshot-copy does what we need. A sr-uuid is provided to it only if it has
        #+ been properly set.
        l_template_uuid=$(xe snapshot-copy                                  \
            uuid="${l_snapshot_uuid}"                                       \
            new-name-label="${start_time}.${vm_name_label}.${snapshot_suffix}" \
            ${l_template_sr_uuid:+"sr-uuid="${l_template_sr_uuid}}) ;
        local l_status=$?

        if [ "0" -eq "${l_status}" ] ; then
            log INFO "template backup created successfully for vm ${l_vm_uuid}."
            log INFO "template uuid: ${l_template_uuid}"
            # Set the parameter template-of (other-config) so that we can search
            #+ for the templates of the VM en masse. Also set the date the template
            #+ was created for future reference.
            xe template-param-set                                               \
                uuid="${l_template_uuid}"                                       \
                other-config:XenCenter.CustomFields.template-of="${l_vm_uuid}"  \
                other-config:XenCenter.CustomFields.created-on="${full_date}";
            # Display the uuid of the created template.
            echo ${l_template_uuid};
        else
            log ERROR "Failed to create template backup for vm ${l_vm_uuid}"
        fi


        # Destroy the snapshot used to backup. 
        #+ snapshot-uninstall seems to be the appropriate command.
        yes yes | xe snapshot-uninstall snapshot-uuid="${l_snapshot_uuid}"
        set_global "snapshot_to_destroy:";

        # See if VM should be started.
        vm_to_start=$(get_global "vm_to_start")
        if [ ! -z "${vm_to_start}" ] ;then
            log INFO "Restarting stopped vm with UUID=${vm_to_start}"
            xe vm-start vm="${vm_to_start}";
            local l_temp_status="$?";
            if [ "0" -ne "${l_temp_status}" ]; then
                xe vm-list uuid="${vm_to_start}" power-state=running | \
                    grep -q -e "${vm_to_start}";
                if [ "0" -eq "$?" ]; then
                    log INFO "VM ${vm_to_start} that was to be restarted already running."
                else
                    log ERROR "Failed restarting VM ${vm_to_start}"
                fi; # /if machine to be restarted already running.
            fi # /if failed to restart machine
            set_global "vm_to_start:";
            status=$(( ${status} | ${l_temp_status} ));
        fi # / if VM should be re-started.

        # Remove all but the n latest backups
        log INFO "Preparing to remove extraneous backups"
        retain_latest_n_backups                 \
            "vm_uuid:${l_vm_uuid}"              \
            "backup_type:template"              \
            "preserve_n:${l_template_backlog}"  ;
        return "${l_status}";
    } # /function create_template_backup



    function create_xva_backup(){
        # Creates the xva_backup
        # Required arguments: Maps of:
            # vm_uuid           : valid uuid
            # backup_type       : xva, template, xva-template, never
            # xva_backup_freq   : daily, weekly, monthly, never
            # backup_live       : yes, 1, true, no, 0, false
            # xva_backlog       : <positive integer or 0>
        # Optional arguments: None
        # The following one-liner replaces the command-line arguments
        #+ passed to the function with an expression that, when evaluated
        #+ locally, produces the desired assignments.
        for i in $(for i in $*; do echo "l_${i}" | sed -e "s/:/=/"; done); do
            log DEBUG "Evaluating ${i}"
            eval local ${i};
        done
        get_if_should_backup "vm_uuid:${l_vm_uuid}"                   \
                             "backup_type:${l_backup_type}"           \
                             "check_for:xva"                          \
                             "template_backup_freq:${l_xva_backup_freq}";
        if [ 0 -ne "$?" ] ;then
            log INFO "xva backup not required for VM with uuid ${l_vm_uuid}."
            return 0;
        fi

        # Get the current name label. Using cut --complement removes only the 
        #+ 'name-label ( RW)' section, preserving the rest of the name,
        #+ including any ':' characters found within it.
        vm_name_label="$( xe vm-list uuid=${l_vm_uuid}      | \
                            grep -e 'name-label'            | \
                            cut --complement -d ':' -f 1    | \
                            sed -e 's/^[ \t]\+//')"

        # If sr is full, skip
        storage_state=$(get_free_space_state "${xva_storage_path}");
        if   [ hard == "${storage_state}" ]; then
            log "ERROR" "Insufficient space remaining on ${xva_storage_path}";
            notify_sysadmin "ERROR" "Hard limit reached for ${xva_storage_path}";
            return 1;
        elif [ soft == "${storage_state}" ]; then
            log "WARNING" "Insufficient space remaining on ${xva_storage_path}";
            notify_sysadmin "WARNING" "Soft limit reached for ${xva_storage_path}";
        fi #/ if a repository is full / not full


        # Get if vm should (can) be stopped for the backup.
        get_should_stop_vm "${l_vm_uuid}"; if [ "0" -eq "$?" ];then
            log INFO "Stopping VM ${l_vm_uuid} for the duration of the backup.";
            set_global "vm_to_start:${l_vm_uuid}"
            xe vm-shutdown vm="${l_vm_uuid}";
        fi # /test if VM should be stopped for the duration of the backup.

        # Create snapshot to have as safeguard before backup.
        l_snapshot_uuid=$( \
            xe vm-snapshot vm="${l_vm_uuid}" \
                new-name-label="${snapshot_prefix}.${today}.${vm_name_label}.${snapshot_suffix}" )
        set_global "snapshot_to_destroy:${l_snapshot_uuid}";
        
        # Create the file from the snapshot.

        # Export snapshot to file. Using eval the variables are replaced with
        #+ their respective values.
        eval "local l_filename=${xva_filename_format}";

        if [ -z "${l_filename}" ]; then
            log ERROR "Filename produced by string ${xva_filename_format} is empty";
            return 1;
        fi

        # TODO How should the case where the file exists be handled?
        if ! { touch "${l_filename}" ; } ;then
            log ERROR "Filename ${l_filename} not writable";
            return 1;
        else
            rm -f "${l_filename}"
        fi

        set_global "partial_file_to_remove:${l_filename}"
        xe snapshot-export-to-template                      \
            snapshot-uuid="${l_snapshot_uuid}"              \
            filename="${l_filename}"                        \
            preserve-power-state=false                      ;
        local l_status="$?"
        
        if [ "0" -eq "${l_status}" ]; then
            set_global "partial_file_to_remove:"
        fi #/ if export to file was successful.


        # Destroy the snapshot used to backup.
        yes yes | xe snapshot-uninstall snapshot-uuid="${l_snapshot_uuid}"
        set_global "snapshot_to_destroy:";
        if [ "0" -eq "${l_status}" ] ; then
            log INFO "XVA backup created successfully for vm ${l_vm_uuid}"
            retain_latest_n_backups                 \
                "vm_uuid:${l_vm_uuid}"              \
                "backup_type:xva"                   \
                "preserve_n:${l_xva_backlog}"
        else
            log ERROR "Failed to create XVA backup for vm ${l_vm_uuid}"
        fi

        vm_to_start="$(get_global vm_to_start)";
        # See if VM should be started.
        if [ ! -z "${vm_to_start}" ] ;then
            log INFO "Restarting stopped vm with UUID=${vm_to_start}"
            xe vm-start vm="${vm_to_start}";
            local l_temp_status="$?";
            if [ "0" -ne "${l_temp_status}" ]; then
                xe vm-list uuid="${vm_to_start}" power-state=running | \
                    grep -q -e "${vm_to_start}";
                if [ "0" -eq "$?" ]; then
                    log INFO "VM ${vm_to_start} that was to be restarted already running."
                else
                    log ERROR "Failed restarting VM ${vm_to_start}"
                fi; # /if machine to be restarted already running.
            fi #/if vm failed to be restarted.
            set_global "vm_to_start:";
            l_status=$(( ${l_status} | ${l_temp_status} ));
        fi # / if VM should be re-started.

        return "${l_status}";
    } # function create_xva_backup



    function initialize_workspace(){
        # This function mounts the nfs share into the appropriate position
        #+ So that it can be used appropriately.
        # Required arguments: None
        # Optional arguments: None
        local l_temp_status="0";
        local status="0";

        # If lockfile already present, then exit.
        if [ -e "${lockfile}" ] ; then
            echo "Lockfile ${lockfile} already present. Exiting."
            return 1;
        fi

        # Touch / create logfile. Exit with failure if not.
        # This reduces the chance of separating the two actions.
        if [ ! -e "${log_full_dir_path}" ] ; then
            mkdir -p "${log_full_dir_path}";
            if [ "0" -ne "$?" ]; then
                echo "Failed to create the logfile."
                return 1;
            fi
        fi # / if full dir path to logfile does not exist.
        touch "${lockfile}"; if [ "0" -ne "$?" ] ;then
            echo "lockfile ${lockfile} not obtainable."
            return 1;
        fi

        # Test if NFS share is already mounted.
        local l_mounts=$(mount);
        echo "${l_mounts}"                  | \
            grep -e "${nfs_mount}"          | \
            grep -q -e "${nfs_mountpoint}"  ; local l_share_is_mounted="$?" ;

        if [ "0" -eq "${l_share_is_mounted}" ] ;then
            log INFO "NFS share already mounted. Will not unmount on exit."
            set_global "unmount_nfs:0";
        else
            mount -t nfs "${nfs_mount}" "${nfs_mountpoint}";
            status="$?";
            if [ "0" -ne "${status}" ]; then
                log ERROR "failed to mount nfs share.";
            fi
        fi #/if mountpoint already mounted.

        if [ ! -e "${xva_storage_path}" ]; then
            log WARNING "xva storage path directory ${xva_storage_path} does not exist. Creating."
            mkdir -p "${xva_storage_path}"; 
            if [ "0" -ne "$?" ]; then
                log ERROR "Couldn't create the backup directory. Exiting"
                return 1;
            fi # /can't create the directory
        fi #/ if backup_directory doesn't exist, create it

        if [ ! -w "${xva_storage_path}" ]; then
            log ERROR "xva storage path not writable. Returning with error";
            return 1;
        fi

        # Remove any 0-size files left in the mountpoint and log folders
        #+ This is necessary to stop 0-length xva backups from replacing
        #+ older but valid xva files
        find ${xva_storage_path} ${log_full_dir_path} \
            -xdev -size 0 -exec rm -f {} \;

        log INFO "Lock obtained by instance $$."
        return "${status}";
    } # /function initialize_workspace





    function cleanup_at_exit(){
        # This function cleans-up at the end of the script run.
        # Releases the lock, and unmounts any directories mounted by the script.
        # Required arguments: None
        # Optional arguments: None
        # NOTE: Code should be SAFE!!

        # Check if lockfile exists, otherwise return at this point.
        if [ ! -e "${lockfile}" ]; then
            log INFO "Lockfile not present, cleanup_at_exit terminating now."
            return 1;
        fi
        snapshot_to_destroy=$(get_global 'snapshot_to_destroy');
        vm_to_start=$(get_global 'vm_to_start');
        unmount_nfs=$(get_global 'unmount_nfs');
        partial_file_to_remove=$(get_global 'partial_file_to_remove');

        # Sync disks.
        status="1";
        l_temp_status="";
        for i in `seq 1 ${sync_retries:-5}`; do
            sync;
            status="$?";
            if [ "0" -eq "${status}" ] ;then
                break;
            fi
        done

        if [ "0" -ne "${status}" ]; then
            log ERROR "Failed to sync disks.";
        fi

        # Destroy leftover snapshots if any.
        if [ ! -z "${snapshot_to_destroy}" ]; then
            log INFO "Destroying leftover snapshot with uuid=${snapshot_to_destroy}";
            yes yes | xe snapshot-uninstall snapshot-uuid="${snapshot_to_destroy}";
            set_global "snapshot_to_destroy:";
        fi # /if snapshot_to_destroy not null

        if [ ! -z "${partial_file_to_remove}" ]; then
            if [ -e "${partial_file_to_remove}" ] ;then
                log INFO "Removing partial file ${partial_file_to_remove}"
                rm -f "${partial_file_to_remove}"
                set_global 'partial_file_to_remove:';
            fi # /if the file to remove exists
        fi # /if there is a partial file to be removed.

        # See if VM should be started.
        if [ ! -z "${vm_to_start}" ] ;then
            log INFO "Restarting stopped vm with UUID=${vm_to_start}"
            xe vm-start vm="${vm_to_start}";
            local l_temp_status="$?";
            if [ "0" -ne "${l_temp_status}" ]; then
                log ERROR "Failed restarting VM ${vm_to_start}"
            fi
            set_global "vm_to_start:";
            status=$(( ${status} | ${l_temp_status} ));
        fi # / if VM should be re-started.


        # Unmount nfs sr.
        if [ "1" -eq "${unmount_nfs}" ] ;then
            log INFO "Unmounting nfs share."
            umount "${nfs_mountpoint}"; status=$(( ${status} | $? ));
        fi
        # Release lock (if taken)
        rm -f "${lockfile}"; l_temp_status="$?";
        if [ "0" -ne "${l_temp_status}" ];then
            log ERROR "Removing lockfile failed."
        fi
        status=$(( ${status} | ${l_temp_status} ));
        return "${status}"
    } # function cleanup_at_exit



  #
### -- Code
#
    nocasematch_status=$(shopt -p nocasematch)
    if [ "help" == "${1}" ] ; then
        usage_instructions
        exit 0;
    fi
    eval "${nocasematch_status}";

    # Trap exit signal to call cleanup_at_exit 
    #+ Do *NOT* call it manually as well, otherwise the code will be run twice.
    trap cleanup_at_exit EXIT;

    message="$( initialize_workspace )"; 
    status="$?"
    if [ "0" -ne "${status}" ] ; then
        log INFO "${message}";
        exit "${status}";
    fi
    log INFO "Successfully initialized workspace. Starting backup";


    # Do for each VM
    count=0;
    for vm_uuid in $(get_all_vm_uuids); do

# FIXME now the checking function handles that.
# Relegate the check on a per VM and per backup type base.
#        count=$(( count + 1));
#        count=$(( count % rescan_limit));
#        if [ "0" -eq "${count}" ];then
#            rescan_sr
#            free_space_state=$(get_sr_free_space_state);
#            if [ "hard" == "${free_space_state}" ];then
#                log ERROR "An SR has reached hard limit. Exiting";
#                break;
#            fi; #/ if an SR has reached hard limit.
#        fi # /if count = restart limit

# FIXME make the return values useful
        for i in $(get_vm_backup_parameters ${vm_uuid}); do
            log DEBUG "Evaluating ${i}"
            eval $i;
        done

        if [ "0" -ne "$?" ] ; then
            log ERROR "Failed to get_vm_backup_parameters for ${vm_uuid}";
            continue;
        fi
        
        create_template_backup                              \
            "vm_uuid:${vm_uuid}"                            \
            "backup_type:${backup_type}"                    \
            "template_backup_freq:${template_backup_freq}"  \
            "backup_live:${backup_live}"                    \
            "template_backlog:${template_backlog}"          \
            "template_sr:${template_sr}"                    ;


        create_xva_backup                           \
            "vm_uuid:${vm_uuid}"                    \
            "backup_type:${backup_type}"            \
            "xva_backup_freq:${xva_backup_freq}"    \
            "backup_live:${backup_live}"            \
            "xva_backlog:${xva_backlog}"            ;


    done; # For to handle each VM

    backup_db_metadata

    # Both below functions are called inside cleanup_at_exit function. Do not 
    #   double-call.
    #clean_workspace;
    #unlock



    log INFO "Backup finished by instance $$"
