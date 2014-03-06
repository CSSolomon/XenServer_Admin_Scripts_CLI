function log(){
    echo $@ 1>&2
}






    function rescan_sr(){
        # Rescans all srs so that their information is updated after creating /
        #+ deleting VM backups.
        # Required arguments: None.
        # Optional arguments: None
        local l_sr_list=( $( xe sr-list --minimal | \
            sed -e "s/,/ /g" ) ); 

        for i in ${l_sr_list[@]}; do
# FIXME
echo "re-scanning SR with uuid ${i}" 1>&2
            xe sr-scan uuid="${i}"
        done # /for all all srs
    } # / function rescan_sr









# Actual Test

rescan_sr
