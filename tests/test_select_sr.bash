
function log(){
    echo $@ 1>&2
}



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
        #+  SR uuid 
        local l_sr_to_probe="${1}";
        local l_status="0";

        if [ ! -z "${l_sr_to_probe}" ] ;then
            xe sr-scan uuid="${l_sr_to_probe}";
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



# FIXME DELETE BELOW LINES
# FIXME DELETE ABOVE LINES

    function get_template_sr_(){
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


# DUMMY FUNCTION
function get_template_sr(){
    echo "option 1: $1" 1>&2
    echo "option 2: $2" 1>&2
}
# END OF DUMMY FUNCTION

# ================================== CODE TO BE TESTED


function test_choose_sr(){
        l_vm_uuid="${1}"
        l_template_sr=$(get_value_by_key $l_vm_uuid template_sr)
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
} #/ test choose sr



# ================================== TEST
for i in $(get_all_vm_uuids) ; do
    test_choose_sr $i
done
