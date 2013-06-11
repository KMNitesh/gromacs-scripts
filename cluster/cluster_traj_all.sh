#!/bin/bash

usage()
{
cat << EOF
usage: $0 options

This script will first generate a job that spawns some number of directories spaced by a large spacer. It will then generate an array hold-job to follow up the first job, a job that runs individual trajectories off of many cores, one for each spawned trajectory.

Requires all with [*]
Requires exactly one of [+]

OPTIONS:
   -h      Show this message
   -o [*]  Output naming scheme; kept consistent between folders & jobs
   -T [*]  Location (with path) of long .mdp file to run at equilibrium; it is run once between folders.
   -s [*]  Location (with path) of short .mdp file to run at equilibrium; it is run once between trajectories in a given folder.
   -f [*]  Location (with path) of .mdp file to run as a trajectory; alternates running with -t
   -c [*]  Location (with path) of .gro file to use as initial configuration, 
   -p [*]  Location (with path) of .top file to use for parameters,
   -t [*]  Location (with path) of .cpt file to use for initial checkpoint, 
   -N      Number of folders to generate (default=100)
   -n      Number of trajectories to generate in each directory (default=100)
   -1 [+]  Setup PBS for hopper@nersc (24 cores per node, each trajectory must utilize a multiple of 24 cores)
   -2 [+]  Setup PBS for catamount@lbl (16 cores per node in cm_normal, if [-P 1] will run trajectories on cm_serial with 1 ppn and equilibration on one node)
   -R      READY TO SUBMIT; pass this argument to run qsub at all appropriate intervals. Without this flag, only .pbs files will be generated.
   -P      Number of processors to request for any instance of the jobs (cluster default)
   -W      Number of warnings allowed by grompp (default=gromacs-default) (-W 1 strongly recommended when bond-lambda values are not set)
   -w      Walltime for prep (trajectories each get 1h on Hopper, default on Hopper = 06:00:00) 
   
EOF
}

NAME=
FOLDMDP=
STEPMDP=
TRAJMDP=
GRO=
CPT=
TOP=
NTRAJ=100
NFOLD=100
VERBOSE=
CLUSTER=
READY=
P_THREAD=
WALL=
WARN=
while getopts “ho:T:s:f:c:p:t:N:n:12RP:W:w:” OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         o)
             NAME=$OPTARG
             ;;
         T)
             FOLDMDP=$OPTARG
             ;;
         s)
             STEPMDP=$OPTARG
             ;;
	 f)
             TRAJMDP=$OPTARG
             ;;
         c)
             GRO=$OPTARG
             ;;
       	 p)
             TOP=$OPTARG
             ;;
       	 t)
             CPT=$OPTARG
             ;;
	 N)
	     NFOLD=$OPTARG
	     ;;
	 n)
	     NTRAJ=$OPTARG
	     ;;
	 1)
	     CLUSTER="HOPPER"
	     ;;
	 2)
	     CLUSTER="CATAMOUNT"
 	     ;;
	 R)
	     READY=1
	     ;;
	 P)
	     P_THREAD=$OPTARG
	     ;;
         W)
             WARN=$OPTARG
             ;;
         w)
             WALL=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

if [[ -z $NAME ]] || [[ -z $FOLDMDP ]] || [[ -z $STEPMDP ]] || [[ -z $TRAJMDP ]] || [[ -z $GRO ]] || [[ -z $CPT ]] || [[ -z $TOP ]] || [[ -z $CLUSTER ]]
then
     echo "Missing required input."
 	echo "NAME: $NAME LongSpacer: $FOLDMDP ShortSpacer $STEPMDP Trajectory $TRAJMDP .groFile $GRO .cptFile $CPT .topFile $TOP cluster $CLUSTER"
     usage
     exit 1
fi

if ! [[ -z $WARN ]]; then
	WARN="-maxwarn $WARN"
fi


if [ $CLUSTER = "HOPPER" ]; then
	echo "Hopper in testing... Hopper also does not accept array jobs!!" 
		
	GROMACS_VERSION='gromacs/4.6.1-sp'
	HOPPERMAGIC="CRAY_ROOTFS=DSL"
	GROMPP="grompp_sp"
	MDRUN1="aprun -n $P_THREAD mdrun_mpi_sp"
	MDRUN2="aprun -n $P_THREAD mdrun_mpi_sp"
	QUEUE1='regular'
	QUEUE2='regular'
	CORE_RESOURCE_1="mppwidth=$P_THREAD"
	CORE_RESOURCE_2="mppwidth=$P_THREAD"


	if ! [[ -z $WALL ]]; then
		WALL="walltime=$WALL"
	else
		WALL="walltime=06:00:00"
	fi

	#---------------------------------------
	# Setup the folders
	#---------------------------------------
	echo "#PBS -N $NAME-gmx-tprep" > $NAME-tprep.pbs
	echo "#PBS -q $QUEUE1" >> $NAME-tprep.pbs
	echo "#PBS -l $CORE_RESOURCE_1" >> $NAME-tprep.pbs
	echo "#PBS -l $WALL" >> $NAME-tprep.pbs
	echo "#PBS -j oe" >> $NAME-tprep.pbs
	echo "#PBS -V" >> $NAME-tprep.pbs
	echo " " >> $NAME-tprep.pbs
	
	#mdrun $CORES times. Make a new directory for each.
	echo "PREVGRO=" >> $NAME-tprep.pbs
	echo "PREVCPT=" >> $NAME-tprep.pbs
	
	echo "module load $GROMACS_VERSION" >> $NAME-tprep.pbs
	echo "$HOPPERMAGIC" >> $NAME-tprep.pbs
	echo 'cd $PBS_O_WORKDIR' >> $NAME-tprep.pbs
	echo "mkdir $NAME-tprep" >> $NAME-tprep.pbs
	echo "cd $NAME-tprep" >> $NAME-tprep.pbs
	
	echo " " >> $NAME-tprep.pbs
	echo "for CTR in $(eval echo {1..$NFOLD})" >> $NAME-tprep.pbs
	echo "do" >> $NAME-tprep.pbs
	echo '	cd $PBS_O_WORKDIR/'"$NAME-tprep" >> $NAME-tprep.pbs
	echo "	mkdir $NAME"'$CTR' >> $NAME-tprep.pbs
	echo "	cd $NAME"'$CTR' >> $NAME-tprep.pbs
	echo "	mkdir INIT" >> $NAME-tprep.pbs
	echo "	mkdir TRAJ" >> $NAME-tprep.pbs
	echo "	cd INIT" >> $NAME-tprep.pbs
	echo '	if [[ -z $PREVGRO ]]' >> $NAME-tprep.pbs
	echo "		then $GROMPP $WARN -f $FOLDMDP -p $TOP -c $GRO -t $CPT -o $NAME"'$CTR' >> $NAME-tprep.pbs
	echo "	else" >> $NAME-tprep.pbs
	echo "		$GROMPP $WARN -f $FOLDMDP -p $TOP "'-c $PREVGRO -t $PREVCPT -o '"$NAME"'$CTR' >> $NAME-tprep.pbs
	echo "	fi" >> $NAME-tprep.pbs
	echo "	$MDRUN1 -deffnm $NAME"'$CTR' >> $NAME-tprep.pbs
	echo '	PREVGRO=$(pwd)/'"$NAME"'$CTR.gro' >> $NAME-tprep.pbs
	echo '	PREVCPT=$(pwd)/'"$NAME"'$CTR.cpt' >> $NAME-tprep.pbs
	echo "done" >> $NAME-tprep.pbs
	
	#Make a copy when done
	echo " " >> $NAME-tprep.pbs
	echo 'cd $PBS_O_WORKDIR' >> $NAME-tprep.pbs
	echo "cp -r $NAME-tprep $NAME-traj" >> $NAME-tprep.pbs


	JOBID=
	if [[ $READY ]]; then
		echo "qsub $NAME-tprep.pbs"
		JOBID=`qsub $NAME-tprep.pbs`
		echo "tprep: $JOBID"
	fi
	
	#---------------------------------------
	# Run the trajectories, array style
	#---------------------------------------
	echo "#PBS -N $NAME-gmx-traj" >> $NAME-traj.pbs
	echo "#PBS -q $QUEUE2" >> $NAME-traj.pbs
	echo "#PBS -l $CORE_RESOURCE_2" >> $NAME-traj.pbs
	echo "#PBS -l walltime=01:00:00" >> $NAME-traj.pbs
	echo "#PBS -j oe" >> $NAME-traj.pbs

	echo 'cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo 'FULL=$(ls INIT | grep "\.cpt$" | head -n 1)' >> $NAME-traj.pbs
	echo 'BASE=${FULL//.cpt/}' >> $NAME-traj.pbs

	echo "module load $GROMACS_VERSION" >> $NAME-traj.pbs
	echo "module load $FFTW" >> $NAME-traj.pbs
	echo "export GMX_MAXBACKUP=-1" >> $NAME-traj.pbs #Prevents crashing due to an overflow of mdrun.mdp files
	echo " " >> $NAME-traj.pbs

	# Run the mini-spacer for an arbitrary time to make sure we continue to sample the equilibrium distribution of initial configs
	echo " " >> $NAME-traj.pbs
	echo 'cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "$GROMPP -f $STEPMDP -p $TOP -c INIT/"'$BASE.gro -t INIT/$BASE.cpt -o INIT/$BASE.1 '"$WARN" >> $NAME-traj.pbs
	echo "cd INIT" >> $NAME-traj.pbs
	echo "$MDRUN2 -v -deffnm "'$BASE.1'" >& qsub_mdrun.log" >> $NAME-traj.pbs


	echo "for (( num=1 ; num <= $NTRAJ ; num++)) ; do" >> $NAME-traj.pbs
	# Run the trajectory for an arbitrary time
	echo '	cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "	cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "	$GROMPP -f $TRAJMDP -p $TOP -c "'INIT/$BASE.$num.gro -t INIT/$BASE.$num.cpt -o TRAJ/traj$num '"$WARN" >> $NAME-traj.pbs
	echo "	cd TRAJ" >> $NAME-traj.pbs
	echo "	$MDRUN2 -v -deffnm traj"'$num'" >& qsub_mdrun.log" >> $NAME-traj.pbs

	# Run the mini-spacer for an arbitrary time to make sure we continue to sample the equilibrium distribution of initial configs
	echo " " >> $NAME-traj.pbs
	echo '	cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "	cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "	$GROMPP -f $STEPMDP -p $TOP -c "'INIT/$BASE.$num.gro -t INIT/$BASE.$num.cpt -o INIT/$BASE.$(($num+1)) '" $WARN" >> $NAME-traj.pbs
	echo "	cd INIT" >> $NAME-traj.pbs
	echo "	$MDRUN2 -v -deffnm "'$BASE.$(($num+1))'" >& qsub_mdrun.log" >> $NAME-traj.pbs
	echo "done" >> $NAME-traj.pbs
# SUBMIT THE SCRIPT
	
	if [ $READY ]; then
		echo "qsub $NAME-traj.pbs -t 1-$NFOLD -W depend=afterok:$JOBID"
		qsub $NAME-traj.pbs -t 1-$NFOLD -W depend=afterok:$JOBID
	fi
fi


if [ $CLUSTER = "CATAMOUNT" ]; then
	echo "Catamount version of this script is not allowed!!! Catamount does not permit hold jobs or array jobs. Not actually tested due to this."
	GROMACS_VERSION=
	GROMPP=
	MDRUN1=
	MDRUN2=
	CORE_RESOURCE_1=
	CORE_RESOURCE_2=
	QUEUE2=
	FFTW='fftw/3.3.2-intel'
	if [ $P_THREAD -gt 1 ]; then
       	GROMACS_VERSION='gromacs/4.6-mpi'
       	GROMPP="mpirun -n 1 grompp_mpi"
       	MDRUN1="mpirun -n $P_THREAD mdrun_mpi"
       	MDRUN2="mpirun -n $P_THREAD mdrun_mpi"
       	QUEUE2='cm_normal'
       	CORE_RESOURCE_1="nodes=$(($P_THREAD/16)):ppn=16:catamount"
       	CORE_RESOURCE_2="nodes=$(($P_THREAD/16)):ppn=16:catamount"
       else
       	GROMACS_VERSION='gromacs/4.6'
       	GROMPP='grompp'
       	MDRUN1='mdrun -nt 16'
       	MDRUN2='mdrun -nt 1'
       	QUEUE2='cm_serial'
       	CORE_RESOURCE_1="nodes=1:ppn=16:catamount"
       	CORE_RESOURCE_2="nodes=1:ppn=1:cmserial"
       fi

       #---------------------------------------
       # Setup the folders
       #---------------------------------------
       echo "#PBS -N $NAME-gmx-tprep" > $NAME-tprep.pbs
       echo "#PBS -q cm_normal" >> $NAME-tprep.pbs
       echo "#PBS -l $CORE_RESOURCE_1" >> $NAME-tprep.pbs
       echo "#PBS -j oe" >> $NAME-tprep.pbs
       echo "#PBS -V" >> $NAME-tprep.pbs
       echo " " >> $NAME-tprep.pbs
       
       #mdrun $CORES times. Make a new directory for each.
       echo "PREVGRO=" >> $NAME-tprep.pbs
       echo "PREVCPT=" >> $NAME-tprep.pbs
       
       echo "module load $GROMACS_VERSION" >> $NAME-tprep.pbs
       echo "module load $FFTW" >> $NAME-tprep.pbs
       echo 'cd $PBS_O_WORKDIR' >> $NAME-tprep.pbs
       echo "mkdir $NAME-tprep" >> $NAME-tprep.pbs
       echo "cd $NAME-tprep" >> $NAME-tprep.pbs
       
       echo " " >> $NAME-tprep.pbs
       echo "for CTR in $(eval echo {1..$NFOLD})" >> $NAME-tprep.pbs
       echo "do" >> $NAME-tprep.pbs
       echo '	cd $PBS_O_WORKDIR/'"$NAME-tprep" >> $NAME-tprep.pbs
       echo "	mkdir $NAME"'$CTR' >> $NAME-tprep.pbs
       echo "	cd $NAME"'$CTR' >> $NAME-tprep.pbs
       echo "	mkdir INIT" >> $NAME-tprep.pbs
       echo "	mkdir TRAJ" >> $NAME-tprep.pbs
       echo "	cd INIT" >> $NAME-tprep.pbs
       echo '	if [[ -z $PREVGRO ]]' >> $NAME-tprep.pbs
       echo "		then $GROMPP $WARN -f $FOLDMDP -p $TOP -c $GRO -t $CPT -o $NAME"'$CTR' >> $NAME-tprep.pbs
       echo "	else" >> $NAME-tprep.pbs
       echo "		$GROMPP $WARN -f $FOLDMDP -p $TOP "'-c $PREVGRO -t $PREVCPT -o '"$NAME"'$CTR' >> $NAME-tprep.pbs
       echo "	fi" >> $NAME-tprep.pbs
       echo "	$MDRUN1 -deffnm $NAME"'$CTR' >> $NAME-tprep.pbs
       echo '	PREVGRO=$(pwd)/'"$NAME"'$CTR.gro' >> $NAME-tprep.pbs
       echo '	PREVCPT=$(pwd)/'"$NAME"'$CTR.cpt' >> $NAME-tprep.pbs
       echo "done" >> $NAME-tprep.pbs
       
       #Make a copy when done
       echo " " >> $NAME-tprep.pbs
       echo 'cd $PBS_O_WORKDIR' >> $NAME-tprep.pbs
       echo "cp -r $NAME-tprep $NAME-traj" >> $NAME-tprep.pbs


       JOBID=
       if [[ $READY ]]; then
       	echo "qsub $NAME-tprep.pbs"
       	#JOBID=`qsub $NAME-tprep.pbs`
       	echo "tprep: $JOBID"
	fi
	
	#---------------------------------------
	# Run the trajectories, array style
	#---------------------------------------
	echo "#PBS -N $NAME-gmx-traj" > $NAME-traj.pbs
	echo "#PBS -q $QUEUE2" >> $NAME-traj.pbs
	echo "#PBS -l $CORE_RESOURCE_2" >> $NAME-traj.pbs
	#echo "#PBS -l walltime=01:00:00" >> $NAME-traj.pbs
	echo "#PBS -j oe" >> $NAME-traj.pbs

	echo 'cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo 'FULL=$(ls INIT | grep "\.cpt$" | head -n 1)' >> $NAME-traj.pbs
	echo 'BASE=${FULL//.cpt/}' >> $NAME-traj.pbs

	echo "module load $GROMACS_VERSION" >> $NAME-traj.pbs
	echo "module load $FFTW" >> $NAME-traj.pbs
	echo "export GMX_MAXBACKUP=-1" >> $NAME-traj.pbs
	echo " " >> $NAME-traj.pbs

	# Run the mini-spacer for an arbitrary time to make sure we continue to sample the equilibrium distribution of initial configs
	echo " " >> $NAME-traj.pbs
	echo 'cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "$GROMPP -f $STEPMDP -p $TOP -c INIT/"'$BASE.gro -t INIT/$BASE.cpt -o INIT/$BASE.1 '"$WARN" >> $NAME-traj.pbs
	echo "cd INIT" >> $NAME-traj.pbs
	echo "$MDRUN2 -v -deffnm "'$BASE.1'" >& qsub_mdrun.log" >> $NAME-traj.pbs


	echo "for (( num=1 ; num <= $NTRAJ ; num++)) ; do" >> $NAME-traj.pbs
	# Run the trajectory for an arbitrary time
	echo '	cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "	cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "	$GROMPP -f $TRAJMDP -p $TOP -c "'INIT/$BASE.$num.gro -t INIT/$BASE.$num.cpt -o TRAJ/traj$num '"$WARN" >> $NAME-traj.pbs
	echo "	cd TRAJ" >> $NAME-traj.pbs
	echo "	$MDRUN2 -v -deffnm traj"'$num'" >& qsub_mdrun.log" >> $NAME-traj.pbs

	# Run the mini-spacer for an arbitrary time to make sure we continue to sample the equilibrium distribution of initial configs
	echo " " >> $NAME-traj.pbs
	echo '	cd $PBS_O_WORKDIR' >> $NAME-traj.pbs
	# Accesses the folder built by $NAME$CTR to match ARRAYID
	echo "	cd $NAME-traj/$NAME"'$PBS_ARRAYID' >> $NAME-traj.pbs
	echo "	$GROMPP -f $STEPMDP -p $TOP -c "'INIT/$BASE.$num.gro -t INIT/$BASE.$num.cpt -o INIT/$BASE.$(($num+1)) '" $WARN" >> $NAME-traj.pbs
	echo "	cd INIT" >> $NAME-traj.pbs
	echo "	$MDRUN2 -v -deffnm "'$BASE.$(($num+1))'" >& qsub_mdrun.log" >> $NAME-traj.pbs
	echo "done" >> $NAME-traj.pbs
# SUBMIT THE SCRIPT
	
	if [ $READY ]; then
       		echo "qsub $NAME-traj.pbs -t 1-$NFOLD -W depend=afterok:$JOBID"
       		#qsub $NAME-traj.pbs -t 1-$NFOLD -W depend=afterok:$JOBID
	fi
fi
