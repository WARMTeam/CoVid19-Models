/******************************************************************
* This file is part of COMOKIT, the GAMA CoVid19 Modeling Kit
* Relase 1.0, May 2020. See http://comokit.org for support and updates
* Author: Alexis Drogoul
* Tags: covid19,epidemiology
******************************************************************/

@no_experiment

model CoVid19

import "Policy.gaml"
import "ActivitiesMonitor.gaml"

global {

	action create_authority {
		ask world { do console_output("Create an authority ", caller::"Authority.gaml");}
		create Authority;
		do define_policy;

	}
	
	action define_policy{}
 
}

/* 
 * Describes the main authority in charge of the health policies to implement
 */
species Authority {
	AbstractPolicy policy <- create_no_containment_policy(); // default
	ActivitiesMonitor act_monitor;
	
	reflex apply_policy {
		ask policy {
			do apply();
		}
	}

	reflex init_stats when: every(#day) and (act_monitor != nil) {
		ask act_monitor { do restart_day;}
	}
	
	action update_monitor(Activity act, bool allowed) {
		if(act_monitor != nil){
			ask act_monitor { 
				do update_stat(act, allowed);
			}			
		} 
	}

	bool allows (Individual i, Activity activity) { 
		bool allowed <- policy.is_allowed(i,activity);
		do update_monitor(activity, allowed);
		return allowed ;
	}
	
	int limitGroupActivity (Individual i, Activity activity) { 
		return policy.max_allowed(i,activity);
	}
	
	
	// ----------------------------------------- //
	//											 //
 	// FACTORY STYLE FUNCTIONS TO BUILD POLICIES //
 	//											 //
 	// ----------------------------------------- //
	
	
	/*
	 * To limit a policiy to be constraint in space: returns the policy (AbstractPolicy) p to
	 * be a SpatialPolicy that is only applied in the given (geometry) area
	 */
	SpatialPolicy in_area (AbstractPolicy p, geometry area) {
		create SpatialPolicy with: [target::p, application_area::area] returns: result;
		return first(result);
	}
	
	/*
	 * To limit a policy to be constraint by time: returns the policy (AbstractPolicy) p to
	 * be a TemporalPolicy that will last for nb_days number of days after policy have been launched
	 */
	TemporaryPolicy during (AbstractPolicy p, int nb_days) {
		create TemporaryPolicy with: [target::p, duration::(nb_days #day)] returns: result;
		return first(result);
	}
	
	/*
	 * To define a policy to be launched considering a given threshold of confirmed cases: returns the policy
	 * (AbstractPolicy) p to start when (int) min number of infected Individual have been confirmed (through tests)
	 */
	CaseRangePolicy from_min_cases (AbstractPolicy p, int min) {
		create CaseRangePolicy with: [target::p, min::min] returns: result;
		return first(result);
	}
	
	/*
	 * To define a policy to stop after a certain amount of confirmed cases: returns the policy
	 * (AbstractPolicy) p to last when (int) max number of infected Individual have been confirmed (through tests)
	 */
	CaseRangePolicy until_max_cases (AbstractPolicy p, int max) {
		create CaseRangePolicy with: [target::p, max::max] returns: result;
		return first(result);
	}
	
	/*
	 * To define a combination of policies: returns a combination of all given (list<AbstractPolicy>) policies 
	 */
	CompoundPolicy combination(list<AbstractPolicy> policies) {
		create CompoundPolicy with: [targets::policies] returns: result;
		return first(result);
	}
	
	/*
	 * To define a tolerance for the applications of policies: returns the (AbstractPolicy) policy p to
	 * be relaxed by (float in [0,1]) tolerance
	 * 
	 * TODO: precise how tolerance works
	 * 
	 */
	PartialPolicy with_tolerance(AbstractPolicy p, float tolerance) {
		create PartialPolicy with: [target::p, tolerance::tolerance] returns: result;
		return first(result);
	}
	
	/*
	 * To define a policy that prohibit every activities
	 */
	ActivitiesListingPolicy create_lockdown_policy {
		create ActivitiesListingPolicy returns: result {
			loop s over: Activities.keys {
				allowed_activities[s] <- false;
			}
		}
		return first(result);
	}
		
	/*
	 * To define a policy that pohibits every activities exept the given (list<string>) of allowed activities.
	 * SEE Model/Constants.gaml for the list of built-in activities; you can also implement your own activities - TODO (how to)
	 */
	ActivitiesListingPolicy create_lockdown_policy_except(list<string> allowed) {
		create ActivitiesListingPolicy returns: result {
			allowed_activities <- Activities.keys as_map (each::allowed contains each);
		}
		return first(result);
	}
	
	/*
	 * To define a policy that prohibit confirmed cases (i.e. Individual that have been positivly tested) 
	 * to exit the home place
	 */
	PositiveAtHome create_positive_at_home_policy {
		create PositiveAtHome  returns: result;
		return first(result);
	}
	
	/*
	 * To define a policy that prohibit the entire family of a confirmed cases (i.e. Individual that have been positivly tested) 
	 * to exit the home place
	 */
	FamilyOfPositiveAtHome create_family_of_positive_at_home_policy {
		create FamilyOfPositiveAtHome returns: result;				
		return first(result);
	}
	
	/*
	 * To define a policy to be applied only on a given proportion of individual: returns the (AbstractPolicy) policy p
	 * that will allows a proportion (float) a of individual to contravene to the restrictions 
	 */
	AllowedIndividualsPolicy with_percentage_of_allowed_individual(AbstractPolicy p, float a) {
		create AllowedIndividualsPolicy with: [target::p, percentage_of_essential_workers::a]  returns: result;
		return (first(result));
	}

	/*
	 * To define a lockdown policy (i.e. not any activity at all) to be applied withing a given radius around a location:
	 * returns a SpatialPolicy that will be applied only in a given space define by a (float) radius around a (point) loc
	 */
	SpatialPolicy create_lockdown_policy_in_radius(point loc, float radius){		
		SpatialPolicy p <- in_area(create_lockdown_policy(), circle(radius) at_location loc);
		return p;
	}
	
	/*
	 * To define a policy that prohibits work, studying, eating, leisure and sport activities
	 */
	AbstractPolicy create_no_meeting_policy {
		create ActivitiesListingPolicy returns: result {
			loop s over: meeting_relaxing_act {
				allowed_activities[s] <- false;
			}
		}
		return (first(result));
	}
	
	/*
	 * To define a policy that will launch test detections with given number of individual tested per day (nb_people_to_test),
	 * for everyone or only the symptomatics (only_symptomatic), with or without re-test (only_not_tested) 
	 */
	AbstractPolicy create_detection_policy(int nb_people_to_test, bool only_symptomatic, bool only_not_tested) {
		create DetectionPolicy returns: result {
			nb_individual_tested_per_step <- nb_people_to_test;
			symptomatic_only <- only_symptomatic;
			not_tested_only <- only_not_tested;
		}
		return (first(result));
	}
	
	/*
	 * To define a policy with ICU, hospitalisation and a given minimum number of test per day
	 */
	AbstractPolicy create_hospitalisation_policy(bool allow_ICU, bool allow_hospitalisation, int nb_tests){
		create HospitalisationPolicy returns: result{
			is_allowing_ICU <- allow_ICU;
			is_allowing_hospitalisation <- allow_hospitalisation;
			nb_minimum_tests <- nb_tests;
		}
		return (first(result));
	}
	
	/*
	 * An empty policy 
	 */
	AbstractPolicy create_no_containment_policy {
		create NoPolicy returns: result;
		return first(result);
	}
	
	/*
	 * To define a policy that allow school and/or work
	 */
	AbstractPolicy createPolicy (bool school, bool work) {
		create ActivitiesListingPolicy returns: result {
			allowed_activities[studying.name] <- school;
			allowed_activities[working.name] <- work;
		}

		return (first(result));
	}
	

}  