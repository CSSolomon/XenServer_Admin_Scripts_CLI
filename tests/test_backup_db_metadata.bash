function log(){
    echo $@ 1>&2
}

    nfs_mountpoint="${NFS_MOUNTPOINT:-/mnt}"; # USER_MODIFIABLE_OPTION
    log_save_dir="${LOG_SAVE_DIR:-logs}"; # USER_MODIFIABLE_OPTION
    log_full_dir_path="${LOG_FULL_DIR_PATH:-${nfs_mountpoint}/${log_save_dir}}"; # USER_MODIFIABLE_OPTION
    xva_backup_dir="${XVA_BACKUP_DIR:-backup}"; # USER_MODIFIABLE_OPTION
    xva_storage_path="${XVA_STORAGE_PATH:-${nfs_mountpoint}/${xva_backup_dir}}"; # USER_MODIFIABLE_OPTION
    full_date=$(date +%Y%m%d);











    function backup_db_metadata(){
        # Creates a backup of the db metadata, including vm-to-uuid correlations.
        # Required arguments: None
        # Optional arguments: None
        # Get IP of pool master.
        local l_pool_ips="";
        local l_current_ip="";
        local l_pif=$( xe pif-list --minimal | sed -e "s/,/ /g" );
        for i in ${l_pif[@]}; do
            l_current_ip=$( xe pif-param-get uuid=${i} param-name=IP | \
                sed -e "s/\./_/g")
            l_pool_ips="${l_pool_ips}-${l_current_ip}";
        done # /for all pifs
        l_pool_ips=$( echo "${l_pool_ips}"  | \
            sed -e "s/-\+/-/g"              \
                -e "s/^-//");

        if [ -z "${l_pool_ips}" ];then
            log ERROR "Couldn't get any IPs for the pool."
            return 1;
        fi #/ if pool physical IPs all blank.
        
        # Create pool-to-vm correspondence file. Store in logs.
        xe vm-list > "${l_pool_ips}.${full_date}.vm_to_uuid.log"

        # Backup db metadata. Store in xva storage path.
        xe pool-dump-database file-name="${xva_storage_path}/${l_pool_ips}.${full_date}.pool_db_dump.bak"
        return 0;
    } # / backup_db_metadata









# Actual Test


backup_db_metadata
