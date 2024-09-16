#!/bin/bash

webdav_folder_name=Jitendra
ip_address=10.188.171.63


echo -e "What type of file contains the test cases robot files?"

read -p 'Press 1 for pipeline.ff.yml or Press 2 for testcases.txt: ' choice

read -p 'Give Path to file: ' path_to_file

get_hostname_model() {
    
    PYCMD=$(cat <<EOF
import yaml
from yaml.loader import SafeLoader

with open("env/localpool.yml") as f:
    data = yaml.load(f, Loader=SafeLoader)
    machine_name = data['test_machines']['common'].keys()[0]
    model_name = data['test_machines']['common'][machine_name]['model']
    print(machine_name+"_"+str(model_name))
EOF
)
    python -c "$PYCMD"
}

get_testcases_pipelineff_yml() {
    
    PYCMD=$(cat <<EOF
import yaml
from yaml.loader import SafeLoader

with open('$path_to_file') as f:
    data = yaml.load(f, Loader=SafeLoader)
    testcases=data['robot_sets'][0]['robot_files']
    for testcase in testcases:
        print(testcase)
EOF
)
    python -c "$PYCMD"
}

if [ $choice == 1 ]
then
$(get_testcases_pipelineff_yml > testcases_temp.txt) 
else
cat testcases.txt > testcases_temp.txt
fi

declare -A hosts

while IFS= read var
do
    [[ "$var" =~ ^[[:space:]]*# ]] && continue
    parentdir=$(dirname "$var")
    env_file=$parentdir/pool.yml
    cp $env_file env/localpool.yml
    firefly -c -e env/localpool.yml $var --debug
    tc_name=$(basename $var .robot)
    hostname_model=$(get_hostname_model)
    hostname=$(echo $hostname_model | cut -d "_" -f 1)
    model=$(echo $hostname_model | cut -d "_" -f 2)
    tc_type=$(echo $tc_name | cut -d "_" -f 4)
    tc_name=$(echo $tc_name | cut -d "_" -f 5-)
    tc_name_with_model=$model\_$tc_type\_$tc_name
    if [ -v "${hosts[$hostname]}" ]
    then
    hosts[$hostname]="$tc_name_with_model "
    else
    hosts[$hostname]="${hosts[$hostname]} $tc_name_with_model"
    fi
    curl -T ./Aggregate_log.html http://$ip_address/webdav/$webdav_folder_name/$hostname\_$tc_name_with_model.html
done < "testcases_temp.txt"

rm testcases_temp.txt env/localpool.yml

echo "<!DOCTYPE html>
<html>
<head>
<title>@LocalRunTestReport</title>
<style>
table, th, td {
  border: 1px solid black;
}
</style>
</head>
<body>
<h1> Cortex QA E2E Local Automation Run Report </h1>" >> "@LocalTestRunReport.html"

for host in "${!hosts[@]}"
do
    # Refining variables to further process it to html
    echo "<h4>$host</h4><table>" >> "@LocalTestRunReport.html"
    declare -A host_tc_type
    IFS=' '
    read -ra tc_array <<< "${hosts[$host]}"
    for tc in "${tc_array[@]}"
    do
        tc_type=$(echo $tc | cut -d "_" -f 2)
        if [ -v "${host_tc_type[$tc_type]}" ]
        then
        host_tc_type[$tc_type]="$tc"
        else
        host_tc_type[$tc_type]="${host_tc_type[$tc_type]} $tc"
        fi
    done
    
    for tc_type in "${!host_tc_type[@]}"
    do
        IFS=' '
        read -ra tc_name_array <<< "${host_tc_type[$tc_type]}"
        no_of_tcs=${#tc_name_array[@]}
        for i in "${!tc_name_array[@]}"
        do
            hyperlink=http://$ip_address/webdav/$webdav_folder_name/$host\_${tc_name_array[$i]}.html
            tc_name=$(echo ${tc_name_array[$i]} | cut -d "_" -f 2- | tr '_' ' ')
            tc_name=${tc_name^}
            if [ $i == 0 ]
            then
            echo "<tr><th rowspan="$no_of_tcs">$tc_type</th><td><a href="$hyperlink">$tc_name</a></td></tr>" >> "@LocalTestRunReport.html"
            else
            echo "<tr><td><a href="$hyperlink">$tc_name</a></td></tr>" >> "@LocalTestRunReport.html"
            fi
        done
    done
    unset host_tc_type
    echo "</table>" >> "@LocalTestRunReport.html"
done

echo "</body></html>" >> "@LocalTestRunReport.html" 

curl -T ./@LocalTestRunReport.html http://$ip_address/webdav/$webdav_folder_name/@LocalTestRunReport.html
rm @LocalTestRunReport.html

no_of_lines=$(wc -l < testcases.txt)

if [ $no_of_lines -lt 2 ]
then
    echo "You can access the testcase report at http://$ip_address/webdav/$webdav_folder_name from the browser"
else
    echo "You can access the testcases reports at http://$ip_address/webdav/$webdav_folder_name from the browser"
fi
