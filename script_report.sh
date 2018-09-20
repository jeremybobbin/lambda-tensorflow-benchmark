#!/bin/bash -e

SUMMARY_NAME="summary.md"

CPU_NAME="$(lscpu | grep "Model name:" | sed -r 's/Model name:\s{1,}//g' | awk '{ print $4 }')";
if [ $CPU_NAME = "CPU" ]; then
  # CPU can show up at different locations
  CPU_NAME="$(lscpu | grep "Model name:" | sed -r 's/Model name:\s{1,}//g' | awk '{ print $3 }')";
fi

GPU_NAME=2080TI

CONFIG_NAME="${CPU_NAME}-${GPU_NAME}"
echo $CONFIG_NAME

DATA_DIR="/home/${USER}/data/imagenet_mini"

ITERATIONS=3

DATA_NAME=imagenet

MODELS=(
  resnet50
  resnet101
  resnet152
  inception3
  inception4
  vgg16
  alexnet
)


CONFIG_NAMES=(
  $CONFIG_NAME
)

VARIABLE_UPDATE=(
  parameter_server
)

DATA_MODE=(
  syn
  real
)

declare -A BATCH_SIZES=(
  [resnet50]=64
  [resnet101]=64
  [resnet152]=32
  [inception3]=64
  [inception4]=16
  [vgg16]=64
  [alexnet]=512
)

MIN_NUM_GPU=1
MAX_NUM_GPU=1


get_benchmark_name() {

  local num_gpus=$1
  local data_mode=$2
  local variable_update=$3
  local distortions=$4

  local benchmark_name="${data_mode}-${variable_update}"

  if $distortions; then
    benchmark_name+="-distortions"
  fi
  benchmark_name+="-${num_gpus}gpus"
  echo $benchmark_name
}

run_report() {
  local model=$1
  local batch_size=$2
  local config_name=$3
  local num_gpus=$4
  local iter=$5
  local data_mode=$6
  local variable_update=$7
  local distortions=$8

  local output="${LOG_DIR}/${model}-${data_mode}-${variable_update}"

  if $distortions; then
    output+="-distortions"
  fi
  output+="-${num_gpus}gpus-${batch_size}-${iter}.log"

  if [ ! -f ${output} ]; then
    image_per_sec=0
  else
    image_per_sec=$(cat ${output}|grep total\ images | awk '{ print $3 }' | bc -l)
  fi
  
  echo $image_per_sec

}

main() {
  local data_mode variable_update distortion_mode model num_gpus iter benchmark_name distortions
  local config_line table_line
  echo "SUMMARY" > $SUMMARY_NAME
  echo "===" >> $SUMMARY_NAME

  echo "| model | input size | param mem | feat. mem | flops | performance |" >> $SUMMARY_NAME
  echo "|-------|------------|--------------|----------------|-------|-------------|" >> $SUMMARY_NAME
  echo "| [resnet-50](reports/resnet-50.md) | 224 x 224 | 98 MB | 103 MB | 4 BFLOPs | 24.60 / 7.70 |" >> $SUMMARY_NAME
  echo "| [resnet-101](reports/resnet-101.md) | 224 x 224 | 170 MB | 155 MB | 8 BFLOPs | 23.40 / 7.00 |" >> $SUMMARY_NAME
  echo "| [resnet-152](reports/resnet-152.md) | 224 x 224 | 230 MB | 219 MB | 11 BFLOPs | 23.00 / 6.70 |" >> $SUMMARY_NAME  
  echo "| [inception-v3](reports/inception-v3.md) | 299 x 299 | 91 MB | 89 MB | 6 BFLOPs | 22.55 / 6.44 |" >> $SUMMARY_NAME
  echo "| [vgg-vd-19](reports/vgg-vd-19.md) | 224 x 224 | 548 MB | 63 MB | 20 BFLOPs | 28.70 / 9.90 |" >> $SUMMARY_NAME
  echo "| [alexnet](reports/alexnet.md) | 227 x 227 | 233 MB | 3 MB | 1.5 BFLOPs | 41.80 / 19.20 |" >> $SUMMARY_NAME

  config_line="Config |"
  table_line=":------:|"
  for config_name in "${CONFIG_NAMES[@]}"; do
    config_line+=" ${config_name} |"
    table_line+=":------:|"
  done

  for num_gpus in `seq ${MAX_NUM_GPU} -1 ${MIN_NUM_GPU}`; do 
    for data_mode in "${DATA_MODE[@]}"; do
      for variable_update in "${VARIABLE_UPDATE[@]}"; do
        for distortions in true false; do

          if [ $data_mode = syn ] && $distortions ; then
            # skip distortion for synthetic data
            :
          else
            benchmark_name=$(get_benchmark_name $num_gpus $data_mode $variable_update $distortions)
          
            echo $'\n' >> $SUMMARY_NAME
            echo "**${benchmark_name}**"$'\n' >> $SUMMARY_NAME
            echo "${config_line}" >> $SUMMARY_NAME
            echo "${table_line}" >> $SUMMARY_NAME
                
            for model in "${MODELS[@]}"; do
              local batch_size=${BATCH_SIZES[$model]}
              result_line="${model} |"
              for config_name in "${CONFIG_NAMES[@]}"; do

                LOG_DIR="/home/${USER}/imagenet_benchmark_logs/${config_name}"

                result=0

                for iter in $(seq 1 $ITERATIONS); do
                  image_per_sec=$(run_report "$model" $batch_size $config_name $num_gpus $iter $data_mode $variable_update $distortions)
                  result=$(echo "$result + $image_per_sec" | bc -l)
                done
                result=$(echo "scale=2; $result / $ITERATIONS" | bc -l)
                result_line+="${result} |"

              done
              
              echo "${result_line}" >> $SUMMARY_NAME
            done 
          fi

        done
      done
    done
  done


}

main "$@"