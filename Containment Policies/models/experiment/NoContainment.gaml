/***
* Name: Corona
* Author: hqngh
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model Corona

import "../Global.gaml"
import "Abstract.gaml"

global {

	init { 
		do global_init;
		do create_authority;
		ask Authority {
			policies << noContainment;
		}

	}

}

experiment "No Containment" parent: "Abstract Experiment" {
	output {
		display "Main" parent: d1 {
		}
		display "Chart" parent: chart {
		}
		display "Cumulative incidence" parent: cumulative_incidence {
		}
	}

}