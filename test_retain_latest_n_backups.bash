
function log(){
    echo $@ 1>&2
}


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
                log "no no no, not good"
                return 1;
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





# =========== CODE to be tested and copied back.

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
                eval local $i;
            done
            if [ "template" == "${l_backup_type}" ] ; then
                # Get all backups that are template-of and ignore the n latest.
				all_vm_templates=( $(													\
                    xe template-list --minimal                                          \
                        other-config:XenCenter.CustomFields.template-of="${l_vm_uuid}"  | \
					sed -e 's/,/\n/g'													));
                older_template_uuids=($( for template_uuid in ${all_vm_templates[@]} ; do 
                        creation_date=$(xe template-param-get               \
                                uuid=${template_uuid}                       \
                                param-name=other-config                     \
                                param-key=XenCenter.CustomFields.created-on );
                        # Templates without creation dates are considered ancient
                        echo "${creation_date:-19000101} ${template_uuid}"; 
                    done                            | \
                    sort							| \
                    cut -d " " -f 2 # FIXME UNCOMMENT | \
# FIXME DELETE BELOW LINES
#                    echo   'yes yes | xe template-uninstall template-uuid="${i}" ';
			))
# FIXME DELETE ABOVE LINES
# FIXME UNCOMMENT   head -n -${preserve_n:-9999}	));
# FIXME DELETE BELOW LINES
				for i in ${older_template_uuids[@]}; do
					echo $i 1>&2;
			    done
#		echo "older templs: ${older_template_uuids[@]}"
#		echo ${older_template_uuids[@]} | sed -e "s/[ \t],\+[ \t]\+/\n/g"
#
#                all_template_uuids=( $(                                               \
#                    xe template-list --minimal                                          \
#                        other-config:XenCenter.CustomFields.template-of="${l_vm_uuid}"  | \
#                            sed -e 's/,/ /g'                          ) )
#                echo "older_template_uuids: ${older_template_uuids[@]}"
#                for k in ${all_template_uuids[@]}; do
#                    echo "${k}"
#                done
# FIXME DELETE ABOVE LINES
# FIXME UNCOMMENT BELOW LINES
#                for i in ${older_template_uuids[@]} ;do
#                    log INFO "removing template with uuid = ${i}";
#                    yes yes | xe template-uninstall template-uuid="${i}";
#                done
# FIXME UNCOMMENT ABOVE LINES
# FIXME DELETE BELOW LINES
#                    echo   'yes yes | xe template-uninstall template-uuid="${i}" ';
			true
# FIXME DELETE ABOVE LINES
                    if [ "0" -ne "$?" ];then
                        log WARNING "Failed to remove template with uuid = ${i}";
                    fi
            elif [ "xva" == "${l_backup_type}" ] ; then
                older_xva_files=( $(                      \
                    ls -1 "${xva_storage_path}"         | \
                        grep -e "${l_vm_uuid}"          | \
                        head -n -"${l_preserve_n}"		));
                for i in ${older_xva_files[@]}; do
                    log INFO "Removing file ${i}";
                    rm -f "${xva_storage_path}/${i}";
                done
                # Get all files that are from this VM and ignore the n latest.
            else
                log ERROR "retain_latest_n_backups: unknown type of backup to retain: ${l_preserve_n}"
                return 1;
            fi

        } # /retain_last_n_backups

# ============== TEST CALLS


for vm_uuid in $(get_all_vm_uuids); do 
    echo "VM $vm_uuid"
    echo ---------------------------------------
        for j in $(get_vm_backup_parameters ${vm_uuid}); do
            eval $j
        done
#        echo "backup_type=$backup_type"
#        echo "xva_backup_freq=$xva_backup_freq"
#        echo "template_backup_freq=$template_backup_freq"
#        echo "backup_live=$backup_live"
#        echo "xva_backlog=$xva_backlog"
        echo "template_backlog=$template_backlog"
#        echo "template_sr=$template_sr"

    echo template:
    echo ---------
    retain_latest_n_backups                 \
        "vm_uuid:${vm_uuid}"              \
        "backup_type:template"              \
        "preserve_n:${template_backlog}"  ;

#    echo xva
#    echo ---
#    retain_latest_n_backups                 \
#        "vm_uuid:${vm_uuid}"              \
#        "backup_type:xva"              \
#        "preserve_n:${xva_backlog}"  ;
#    echo -e "=====================================\n"
    
    
done 
