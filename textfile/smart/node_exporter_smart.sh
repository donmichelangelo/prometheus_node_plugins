#!/bin/bash

set -e

SCRAPE_NORMAL=
SCRAPE_LSI=

LSI_ARRAY=

declare -a DRIVES
declare -a RAW_VALUE
declare -a LSI_DRIVES


source /opt/node_exporter_textfile/env.sh



function CommandExists() {
    type "$1" &> /dev/null ;
}

function GetDrives() {

if [[ $SCRAPE_LSI = 1 ]]
then
       
        test -e $MEGA_CLI_BIN
    
        if [[ $? == 1 ]]
        then

            echo "MEGA_CLI_BIN has been not set in env.sh!"
            echo "Going to try to find it via PATH"
            
            for i in "MegaCli64 megacli64 megacli"
            do
                if command_exists $i
                then

                    MEGA_CLI_BIN=$i
                    break

                else
    
                    echo "Couldn't find MegaCli64/megacli64 or megacli in \$PATH either, Exit."
                    exit 1

                fi

                
            done
          

        fi


        for GET_LSI_DRIVES in $($MEGA_CLI_BIN -pdlist -$LSI_ADAPTER_ID -NoLog | grep 'Device Id' |awk ' { print $ 3 } ')
        do

            LSI_DRIVES+="echo $GET_LSI_DRIVES "

        done
    
    
    else

    for GET_DRIVE in $(cat /proc/partitions | awk ' { print $4 } ' | egrep "(s|h).*[a-z]$")
    do
        DRIVES+="/dev/$GET_DRIVE "

    done

fi
}

function GetRawSmartMetrics() {

if [[ $SCRAPE_LSI = 1 ]]
then

    for LSI_DRIVE in ${LSI_DRIVES[*]}
    do
	echo "${LSI_DRIVES[*]}"
        RAW_LSI_VALUE+=$(smartctl -d sat+megaraid,$LSI_DRIVE -A $LSI_ARRAY | awk '/;/{f=1;};f{print;};/ID#/{f=1;}' | sed '$d' | awk ' { print "'$LSI_ARRAY'_Id'$LSI_DRIVE'"","$2","$10"; "} ')

    done


else

    
    #get the raw values of each drive
    for DRIVE in ${DRIVES[*]}
    do
        RAW_VALUE+=$(smartctl -A $DRIVE | awk '/;/{f=1;};f{print;};/ID#/{f=1;}' | sed '$d' | awk ' { print "'$DRIVE'"","$2","$10"; " } ')
    done

fi

}


function FlushResults() {
if [[ $SCRAPE_LSI = 1 ]]
then
    echo -n "" > $NODE_TEXTFILE_DIR/smart_lsi.prom

else

    #flush the previous results
    echo -n "" > $NODE_TEXTFILE_DIR/smart.prom

fi
}


function AssembleMetrics() {

if [[ $SCRAPE_LSI = 1 ]]
then

    for LSI_VALUES in ${RAW_LSI_VALUE[@]}
    do
        IFS=';'
        echo $LSI_VALUES
        DRIVE=$(echo $LSI_VALUES | cut -d',' -f1)
        LSI_VALUE_NAME=$(echo $LSI_VALUES | awk -F',' ' { print $2 } ')
        LSI_VALUE=$(echo $LSI_VALUES | awk -F',' ' { print $3 } ')
        echo "node_smart{drive=\"$DRIVE\",name=\"$LSI_VALUE_NAME\"} $LSI_VALUE" >> $NODE_TEXTFILE_DIR/smart_lsi.prom

    done


else



    for VALUES in ${RAW_VALUE[@]}
    do
        IFS=';'
        echo $VALUES
        DRIVE=$(echo $VALUES | cut -d',' -f1)
        VALUE_NAME=$(echo $VALUES | awk -F',' ' { print $2 } ')
        VALUE=$(echo $VALUES | awk -F',' ' { print $3 } ')
        echo "node_smart{drive=\"$DRIVE\",name=\"$VALUE_NAME\"} $VALUE" >> $NODE_TEXTFILE_DIR/smart.prom

    done
fi

}


while test $# != 0; do
    case "$1" in
        normal)
                SCRAPE_NORMAL=1
                GetDrives
                GetRawSmartMetrics
                FlushResults
                AssembleMetrics

        ;;
        lsi)
                SCRAPE_LSI=1
                GetDrives
                GetRawSmartMetrics
                FlushResults
                AssembleMetrics
        ;;
    -\?|-h|--help)
      echo "$(basename "$0") [options]"
      echo '  '
      echo 'use these switches to define what you want to get scraped:'
      echo '  normal        - scrapes SMART metrics of your HDDs that are connected to your local S-ATA controller'
      echo '  lsi           - scrapes SMART metrics of your HDDs that are connected to a MegaRaid controller (origin Adapter 0 = a0)'
      exit 0
      ;;
    *)
      echo 'Unrecognised argument "'"$1"'"'
      exit 2
      ;;
  esac
  shift
done

