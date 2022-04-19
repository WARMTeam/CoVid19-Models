/******************************************************************
* This file is part of COMOKIT, the GAMA CoVid19 Modeling Kit
* Relase 1.0, May 2020. See http://comokit.org for support and updates
* 
* This file contains global declarations of actions and attributes, used
* mainly for the purpose of initialising the model in experiments
* 
* Author: Benoit Gaudou, Damien Philippon, Patrick Taillandier
* Tags: covid19,epidemiology
******************************************************************/

@no_experiment

model CoVid19
 
import "Entities/Abstract Activity.gaml"

import "Entities/Vaccine.gaml" 

import "Entities/Virus.gaml"

import "Functions.gaml"
   

global {
	//geometry shape <-envelope(shape_file(shp_boundary_path));
	list<AbstractIndividual> all_individuals <- []; 
	
	list<string> possible_homes ;  //building type that will be considered as home	
	map<string, list<string>> activities; //list of activities, and for each activity type, the list of possible building type
	
	int current_day <- starting_date.day_of_week - 1 update: current_date.day_of_week - 1;
	int current_hour <- starting_date.hour update: current_date.hour;
	
	bool politic_is_active <- false;
	float t_ref <- machine_time;
	float t_ref2 <- machine_time;
	
	bool firsts <- true;
	reflex e when: firsts {
		t_ref2 <- machine_time;
		firsts <- false;
	}
	
	
	action init_building_type_parameters {
		file csv_parameters <- csv_file(building_type_per_activity_parameters,",",true);
		matrix data <- matrix(csv_parameters);
		// Modifiers can be weights, age range, or anything else
		list<string> available_modifiers <- [WEIGHT,RANGE];
		map<string,string> activity_modifiers;
		//Loading the different rows number for the parameters in the file
		loop i from: 0 to: data.rows-1{
			string activity_type <- data[0,i];
			bool modifier <- available_modifiers contains activity_type;
			list<string> bd_type;
			loop j from: 1 to: data.columns - 1 {
				if (data[j,i] != nil) {	 
					if modifier {
						activity_modifiers[data[j,i-1]] <- data[j,i]; 
					} else {
						if data[j,i] != nil or data[j,i] != "" {bd_type << data[j,i];}
					}
				}
			}
			if not(modifier) { activities[activity_type] <- bd_type; }
		}
		
		if activities contains_key act_studying {
			loop acts over:activities[act_studying] where not(possible_schools contains_key each) {
				pair age_range <- activity_modifiers contains_key acts ? 
					pair(split_with(activity_modifiers[acts],SPLIT)) : pair(school_age::active_age); 
				possible_schools[acts] <- [int(age_range.key),int(age_range.value)];
			}
			remove key: act_studying from:activities;
		}
		
		if activities contains_key act_working {
			loop actw over:activities[act_working] where not(possible_workplaces contains_key each) { 
				possible_workplaces[actw] <- activity_modifiers contains_key actw ? 
					float(activity_modifiers[actw]) : 1.0;
			}
			remove key: act_working from:activities;
		}
		
		if activities contains_key act_home {
			possible_homes<- activities[act_home];
			remove key: act_home from:activities;
		}
	}
 
	
	/*
	 * Initialization of global epidemiological mechanism in the model, such as environmental contamination, allow individual viral load or not, proportion of agent wearing mask, etc.
	 */
	action init_epidemiological_parameters {
		do console_output("Init epidemiological global parameters ---");
		if(load_epidemiological_parameter_from_file and file_exists(epidemiological_parameters)) {
			float t <- machine_time;
			// Read the file data
			file csv_parameters <- csv_file(epidemiological_parameters,true);
			matrix data <- matrix(csv_parameters);
			
			// found header schem
			int detail_idx <- data.columns - epidemiological_csv_params_number;
			int val_idx <- detail_idx+1;
			
			map<string,int> read_entry_idx;
			loop h from:1 to:data.columns-epidemiological_csv_params_number-1 { 
				switch  data[0,h] { match AGE {read_entry_idx[AGE] <- h;} match SEX {read_entry_idx[SEX] <- h;}  match COMORBIDITIES {read_entry_idx[COMORBIDITIES] <- h;} }
			}
			
			if not(empty(read_entry_idx)) {error "Global epidemiological parameters dependant over "+read_entry_idx.keys
				+" are not yet supported, please consider raising an issue if feature required - https://github.com/COMOKIT/COMOKIT-Model/issues";
			}
			
			loop l from:1 to:data.rows-1 {
				
				string param <- data[l,epidemiological_csv_column_name];
				
				if not(forced_epidemiological_parameters contains param) {
					
					string detail  <- data[l,detail_idx];
					float val <- detail=epidemiological_fixed ?  float(data[l,val_idx]) : world.get_rnd_from_distribution(detail, float(data[l,val_idx]),float(data[l,val_idx+1]));
					
					switch param {
						match epidemiological_transmission_human { init_selfstrain_reinfection_probability <- val; }
						match epidemiological_allow_viral_individual_factor{ allow_viral_individual_factor <- bool(data[l,val_idx]); }
						match epidemiological_transmission_building{ allow_transmission_building <- bool(data[l,val_idx]); }
						match epidemiological_basic_viral_decrease { basic_viral_decrease <- val; }
						match epidemiological_basic_viral_release{  basic_viral_release  <- val; }
						match epidemiological_successful_contact_rate_building{ successful_contact_rate_building <- val; }
						match proportion_antivax { init_all_ages_proportion_antivax <-  val; }
						match epidemiological_proportion_wearing_mask{ init_all_ages_proportion_wearing_mask <- val; }
						match epidemiological_factor_wearing_mask{ init_all_ages_factor_contact_rate_wearing_mask <- val; }
					}
				}
				
			}
			do console_output("\t process parameter files in "+with_precision((machine_time-t)/1000,2)+"s");
		}
	}
	
	/*
	 * Initialize SARS-CoV-2 and variants from files, force parameters and/or default parameters
	 * TODO : test it - damne it's so complicated -  and is clearly not flexible enough for Individual and Biological Entity (they do not have sex)
	 */
	action init_sars_cov_2  {
		do console_output("Init sars-cov-2 and variants ---");
		float t <- machine_time;
		
		csv_file epi_params <- load_epidemiological_parameter_from_file and file_exists(sars_cov_2_parameters) ? csv_file(sars_cov_2_parameters,false) : nil;
		map<map<string,int>,map<string,list<string>>> virus_epidemiological_default_profile <- init_sarscov2_epidemiological_profile(epi_params);
		
		// ----------------------------
		//  CREATION OF SARS-CoV-2
		create sarscov2 with:[source_of_mutation::nil,name::SARS_CoV_2,epidemiological_distribution::virus_epidemiological_default_profile] returns: original_sars_cov_2;
		original_strain <- first(original_sars_cov_2);
		do console_output("\t----"+sample(first(original_sars_cov_2).get_epi_id()));
		do console_output("\tSars-CoV-2 original strain created ("+with_precision((machine_time-t)/1000,2)+"s)");
		t <- machine_time;
		
		// Creation of variant
		if folder_exists(variants_folder) and not(empty(folder(variants_folder))) {
			list<string> variant_files <- folder(variants_folder).contents;
			loop vf over:variant_files where (file_exists(each)) {
				map<map<string,int>,map<string,list<string>>> variant_profile <- init_sarscov2_epidemiological_profile(csv_file(vf,false));
				string variant_name <- first(last(vf split_with "/") split_with ".");
				create sarscov2 with:[source_of_mutation::original_strain,epidemiological_distribution::variant_profile] returns: variants;
				VOC <+  first(variants); // TODO should specify the source of mutation and type of variant (i.e. VOC or VOI)
			}
		} else { do init_variants; }
		
		do console_output("\tVariants created - VOC:"+VOC collect each.name+" - VOI:"+VOI collect each.name+" ("+with_precision((machine_time-t)/1000,2)+"s)");
	}
	
	/*
	 * Initialize an epidemiological profile: <p>
	 * <ul>
	 *  <i> key - AGE-SEXE-COMORBIDITIES
	 *  <i> value::key - epidemiological aspect
	 *  <i> value::value - type of distribution, param1, param2
	 * </ul>
	 * Can be used to init any variants - csv file should be loaded without header
	 */
	map<map<string,int>,map<string,list<string>>> init_sarscov2_epidemiological_profile(csv_file parameters <- nil) {
		map<map<string,int>,map<string,list<string>>> profile <- map([]);
		
		// If there is a parameter file
		if(parameters != nil){
			
			matrix data <- matrix(parameters);
			
			// FOUND HEADERS
			map<string,int> read_entry_idx;
			loop h from:1 to:data.columns-epidemiological_csv_params_number-1 { 
				switch lower_case(string(data[h,0])) { 
					match AGE {read_entry_idx[AGE] <- h;} 
					match SEX {read_entry_idx[SEX] <- h;}  
					match COMORBIDITIES {read_entry_idx[COMORBIDITIES] <- h;}
				}
			}
			
			// write sample(read_entry_idx);
			
			// FIRST ROUND TO FOUND USER ENTRIES
			map<string,list<pair<map<string,int>,list<string>>>> var_to_user_entries_and_params  <- [];
			list<int> params_idx;
			loop pi from:1 to:epidemiological_csv_params_number { params_idx <+ data.columns - pi; }
			params_idx <-  params_idx sort each;
			
			// Read each line of parameter file
			loop i from:  1 to:data.rows-1 {
				string var <- data[epidemiological_csv_column_name,i];
				
				// Record entries, i.e. age x sex x comorbidities
				map<string,int> entry <- [];
				loop e over:read_entry_idx.keys {
					string v <-  data[read_entry_idx[e],i];
					if v != nil and v != "" and not(empty(v)) { entry[e] <- int(v); }
				}
				
				// Record parameters, i.e. detail x  param 1 x param 2
				list<string> params;
				loop pi over:params_idx { params <+ data[pi,i]; }
				
				// write "Process (l"+i+") var "+var+" "+sample(entry)+" => "+params;
				
				if not(var_to_user_entries_and_params contains_key var) {var_to_user_entries_and_params[var] <- [];}
				var_to_user_entries_and_params[var] <+ entry::params;
			}
			
			// SECOND ROUND TO FIT REQUESTED DISTRIBUTION WITH USER ENTRIES
			loop v over:var_to_user_entries_and_params.keys {
				
				// For a given variable of the virus get all possible pair of entry :: parameter
				// i.e.  [AGE,SEX,COMORBIDITIES] x [detail,param1,param2]
				// the map key may be empty, or contains one or more of the 3 given dimensions
				list<pair<map<string,int>,list<string>>> matches <- var_to_user_entries_and_params[v];
				
				// If there is only one parameter line for this variable, then ignore all entry (i.e. no age, sex or comorbidities determinants)
				if length(matches) = 1 {
					if not(profile contains_key epidemiological_default_entry) { profile[epidemiological_default_entry] <- [];} 
					profile[epidemiological_default_entry][v] <- first(matches).value;
				}  else {
					//  Turn parameter file age range into fully explicit integer age
					map<int,list<int>>  age_entry_mapping <- [];
					if (read_entry_idx contains_key AGE) and (matches all_match (each.key contains_key AGE)) {
						list<int> age_range <- matches collect (each.key[AGE]) sort (each);
						if length(age_range)=1 and (first(age_range)=0 or first(age_range)=max_age) {}
						else {
							list<int> ages <- [];
							age_range >- first(ages);
							loop age  from:first(ages) to:max_age {
								if first(age_range) = age { 
									age_entry_mapping[first(ages)] <- ages; ages <- []; age_range >- age;
								}
								ages <+ age;
							}
							age_entry_mapping[first(ages)] <- ages;
						}
					}
					//  Adapt all entries to actual age
					loop em over:matches {
						map<string, int> current_entry <- copy(em.key);
						if empty(age_entry_mapping) { 
							current_entry[] >- AGE;
							if empty(current_entry) { current_entry <- epidemiological_default_entry;}
							if not(profile contains_key current_entry) {profile[current_entry]  <- [];}
							profile[current_entry][v] <- em.value;
						} else {
							loop actual_age over:age_entry_mapping[current_entry[AGE]] {
								map<string,int> actual_entry  <- copy(current_entry);
								actual_entry[AGE] <- actual_age;
								if not(profile contains_key actual_entry) { profile[actual_entry]  <- []; }
								profile[actual_entry][v] <- em.value;
							}
						}
					}	
				}
			}
		
			

		}
		// There is no parameter file
		else {
			 forced_sars_cov_2_parameters <-  SARS_COV_2_EPI_PARAMETERS + SARS_COV_2_EPI_FLIP_PARAMETERS;
		}
		
		map<string,list<string>> default_vals;
		//write "Init default and missing parameters - "+sample(SARS_COV_2_PARAMETERS);
		
		//In the case the user wanted to load parameters from the file, but change the value of some of them for an experiment, 
		// the force_parameters list should contain the key for the parameter, so that the value given will replace the one already
		// defined in the matrix
		loop aParameter over: SARS_COV_2_PARAMETERS  {
			list<string> params;
			switch aParameter {	
				// Fixe values
				match epidemiological_successful_contact_rate_human{ params <- [epidemiological_fixed,init_all_ages_successful_contact_rate_human]; }
				match epidemiological_factor_asymptomatic{ params <- [epidemiological_fixed,init_all_ages_factor_contact_rate_asymptomatic]; }
				match epidemiological_proportion_asymptomatic{ params <- [epidemiological_fixed,init_all_ages_proportion_asymptomatic]; }
				match epidemiological_proportion_death_symptomatic{ params <- [epidemiological_fixed,init_all_ages_proportion_dead_symptomatic];}
				match epidemiological_probability_true_positive{ params <- [epidemiological_fixed,init_all_ages_probability_true_positive]; }
				match epidemiological_probability_true_negative{ params <- [epidemiological_fixed,init_all_ages_probability_true_negative]; }
				match epidemiological_immune_evasion { params <- [epidemiological_fixed, init_immune_escapement]; }
				match epidemiological_reinfection_probability {  params <- [epidemiological_fixed, init_selfstrain_reinfection_probability];}
				
				match epidemiological_viral_individual_factor { params <- 
					[init_all_ages_distribution_viral_individual_factor,string(init_all_ages_parameter_1_viral_individual_factor),string(init_all_ages_parameter_2_viral_individual_factor)];
				}
				
				match epidemiological_incubation_period_symptomatic{ params <- 
					[init_all_ages_distribution_type_incubation_period_symptomatic, string(init_all_ages_parameter_1_incubation_period_symptomatic),string(init_all_ages_parameter_2_incubation_period_symptomatic)]; 
				}
				
				match epidemiological_incubation_period_asymptomatic{params <- 
					[init_all_ages_distribution_type_incubation_period_asymptomatic,string(init_all_ages_parameter_1_incubation_period_asymptomatic),string(init_all_ages_parameter_2_incubation_period_asymptomatic)]; 
				}
				
				match epidemiological_serial_interval{params <- [init_all_ages_distribution_type_serial_interval,string(init_all_ages_parameter_1_serial_interval),string(init_all_ages_parameter_2_serial_interval)]; }
				match epidemiological_infectious_period_symptomatic{ params <-
					[init_all_ages_distribution_type_infectious_period_symptomatic,string(init_all_ages_parameter_1_infectious_period_symptomatic),string(init_all_ages_parameter_2_infectious_period_symptomatic)];
				}
				
				match epidemiological_infectious_period_asymptomatic{ params <- 
					[init_all_ages_distribution_type_infectious_period_asymptomatic,string(init_all_ages_parameter_1_infectious_period_asymptomatic),string(init_all_ages_parameter_2_infectious_period_asymptomatic)];
				}
				
				match epidemiological_proportion_hospitalisation{ params <- [epidemiological_fixed,init_all_ages_proportion_hospitalisation]; }
				match epidemiological_onset_to_hospitalisation{ params <- 
					[init_all_ages_distribution_type_onset_to_hospitalisation,string(init_all_ages_parameter_1_onset_to_hospitalisation),string(init_all_ages_parameter_2_onset_to_hospitalisation)];
				}
				
				match epidemiological_proportion_icu{ params  <- [epidemiological_fixed,init_all_ages_proportion_icu]; }
				match epidemiological_hospitalisation_to_ICU{ params <- 
					[init_all_ages_distribution_type_hospitalisation_to_ICU,string(init_all_ages_parameter_1_hospitalisation_to_ICU),string(init_all_ages_parameter_2_hospitalisation_to_ICU)];
				}
				match epidemiological_stay_ICU{ params  <- [init_all_ages_distribution_type_stay_ICU,string(init_all_ages_parameter_1_stay_ICU),string(init_all_ages_parameter_2_stay_ICU)];}
				default{ /*There is no sens to have a default value for all parameters, or may be 42 */}
			}
				
			default_vals[aParameter] <- params;
			if forced_sars_cov_2_parameters contains aParameter { 
				loop k over:profile.keys {
					if profile[k] contains_key aParameter {
						profile[k][aParameter] <- params;
					}
				}
			}
		}
		
		// In any case, we should have a default value in the distribution of epidemiological attributes, that gives a value whatever epidemiological entry is
		if not(profile contains_key epidemiological_default_entry) { profile[epidemiological_default_entry] <-  default_vals; }
		else {
			loop p over:default_vals.keys - profile[epidemiological_default_entry].keys {  
				profile[epidemiological_default_entry][p] <-  default_vals[p]; 
			}
		}
		
		return profile;
	}
	
	
	
	 /*
	  * Initialize vaccines based on given parameters (default or TODO parameter file)
	  */
	 action init_vaccines {
	 	do console_output("Init vaccines ----");
	 	float t <- machine_time;
	 	
	 	ARNm <+ create_covid19_vaccine(pfizer_biontech,length(pfizer_doses_immunity),pfizer_doses_schedule,pfizer_doses_immunity,
	 		pfizer_doses_sympto=nil?list_with(length(pfizer_doses_immunity),0.0):pfizer_doses_sympto,
	 		pfizer_doses_sever=nil?list_with(length(pfizer_doses_immunity),0.0):pfizer_doses_sever
	 	);
	 	Adeno <+ create_covid19_vaccine(astra_zeneca,length(pfizer_doses_immunity),astra_doses_schedule,astra_doses_immunity,
	 		astra_doses_sympto=nil?list_with(length(astra_doses_immunity),0.0):astra_doses_sympto,
	 		astra_doses_sever=nil?list_with(length(astra_doses_immunity),0.0):astra_doses_sever
	 	);
	 	vaccines <- ARNm + Adeno;
	 	
	 	do console_output("\tVaccines: "+vaccines collect (each.name)+" created ("+with_precision((machine_time-t)/1000,2)+"s)");
	 }

	// ------------- //
	// EMPTY METHODS // 
	
	/*
	 * Add actions to be triggered before COMOKIT initializes
	 */
	action before_init {}
	
	/*
	 * Add actions after COMOKIT have been initialized but before starting simulation
	 */
	action after_init {}
	
	// ----- //
	// DEBUG //
	// ----- //
	
	// Global debug mode to print in console all messages called from #console_output()
	bool DEBUG <- true;
	bool SAVE_LOG <- false;
	string log_name <- "log.txt";
	list<string> levelList const:true <- ["trace","debug","warning","error"]; 
	// the available level of debug among debug, error and warning (default = debug)
	string LEVEL init:"debug" among:["trace","debug","warning","error"];
	// Simple print_out method
	action console_output(string output, string caller <- "Global.gaml", string level <- LEVEL) { 
		if DEBUG {
			string msg <- "["+caller+"] "+output;
			if levelList index_of LEVEL <= levelList index_of level {
				switch level {
					match "error" {error msg;}
					match "warning" {warn msg;}
					default {write msg;}
				}	
			}
			if SAVE_LOG {save msg to:log_name rewrite: false type:text;}
		}
	}
	
	// --------- //
	// BENCHMARK //
	// --------- //
	
	bool BENCHMARK <- false;
	float p1;float p2;float p3;float p4;float p5;float p6;float p7;float p8;float p9;float p10;
	float p11;float p12;float p13;float p14;float p15;float p16;float p17;float p18;float p19;float p20;
	
	
	
	map<string,float> bench <- [
		"Abstract Batch Experiment.observerPattern"::0.0,
		"Authority.apply_policy"::0.0,
		"Authority.init_stats"::0.0,
		"Biological Entity.infect_others"::0.0,
		"Biological Entity.update_time_before_death"::0.0,
		"Biological Entity.update_time_in_ICU"::0.0,
		"Building.update_viral_load"::0.0,
		"Individual.become_infected_outside"::0.0,
		"Individual.infect_others"::0.0,
		"Individual.execute_agenda"::0.0,
		"Individual.update_epidemiology"::0.0,
		"Individual.add_to_dead"::0.0,
		"Individual.add_to_hospitalised"::0.0,
		"Individual.add_to_ICU"::0.0
	];
	
	reflex benchmark_info when:BENCHMARK and every(10#cycle) {
		write bench;
	}

}