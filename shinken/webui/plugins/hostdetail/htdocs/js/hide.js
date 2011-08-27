/* We delare the sliding actions for the advanced ones*/

window.addEvent('domready', function(){
	var adv_actions_slide = new Fx.Slide('advanced_actions');
	adv_actions_slide.hide();
	
	$('toggle_advanced_actions').addEvent('click', function(e){
		e = new Event(e);
		adv_actions_slide.toggle();
		e.stop();
	    });
    });




/* Now a function for managingthe hovering of the problems. Will make
   appears the actiosn buttons with a smoot way (opacity)*/

window.addEvent('domready', function(){
    
    /* We must avoid $$() call for IE, so call a standad way*/
    var switches = $(document.body).getElement('.switches');
    var host_services = $(document.body).getElement('.host-services');

    // We set display actions on hover
    switches.addEvent('mouseenter', function(){
	    new Fx.Tween(switches, {property: 'opacity'}).start(1);
    });

    // And on leaving, hide them with opacity -> 0
    switches.addEvent('mouseleave', function(){
	    new Fx.Tween(switches, {property: 'opacity'}).start(0.5);
    });

    // Now All Services
    // We set display actions on hover
    host_services.addEvent('mouseenter', function(){
            new Fx.Tween(host_services, {property: 'opacity'}).start(1);
	});

    // And on leaving, hide them with opacity -> 0
    host_services.addEvent('mouseleave', function(){
            new Fx.Tween(host_services, {property: 'opacity'}).start(0.5);
	});



});