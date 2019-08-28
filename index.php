<?php

/**
 *
 * index.php
 *
 * This is the System Config UI app.
 *
 * This file is a router; is part of the C in MVC.
 *
 * --------------------------------------------------------------------------------------------------
 *  Copyright (c) 2017 Micron Technology, Inc. All Rights Reserved.
 *
 *  USE OF A COPYRIGHT NOTICE IS PRECAUTIONARY ONLY AND DOES NOT IMPLY PUBLICATION OR DISCLOSURE.
 *
 *  THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION AND TRADE SECRETS OF MICRON TECHNOLOGY, INC.
 *  USE, DISCLOSURE, OR REPRODUCTION IS PROHIBITED WITHOUT THE PRIOR EXPRESS WRITTEN PERMISSION
 *  OF MICRON TECHNOLOGY, INC.
 * --------------------------------------------------------------------------------------------------
 */


// This file is part of your app -- is not part of SIG Web Components.
//
// For global vars available, demos, and other SIG Web Components information,
// see https://sigprism2/swc_demo/  Git Fetch and pull demo

//-----------------------------------------------------------------------------
// Let the user know why the app is not working if the required sig_web_components version is not installed.


// This macro is fixed up in the makefile. Specify the major version of sig_web_components in app_config.json.
if (!file_exists($_SERVER['DOCUMENT_ROOT'] . '/sig_web_components_8.5.0' . '/sig/php/boilerplate.php'))
{
   $app_dirs = explode('/', dirname($_SERVER['PHP_SELF']));
   $app_dir  = $app_dirs[1] . '/';                                  // Do a two-step for PHP 5.3.
   $app_full_dir = $_SERVER['DOCUMENT_ROOT'] . '/' . $app_dir;

   ini_set('error_log', $app_full_dir . 'logs/php_log');

   $msg_text = 'The required library ' . $_SERVER['DOCUMENT_ROOT'] . '/sig_web_components_8.5.0' . ' is not installed. Please contact the server administrator.';

   error_log($msg_text);

   $msg = '<div style="color:silver; background-color:#1B1E22;width:100%;height:100%;font-family:sans-serif"><br>' .
          '  <p style="margin-left:40px;">' . $msg_text .
          '</p></div>';

   echo $msg;
   exit;
}
require_once $_SERVER['DOCUMENT_ROOT'] . '/sig_web_components_8.5.0' . '/sig/php/boilerplate.php';   // Includes authentication route handlers


//-----------------------------------------------------------------------------
// Include app-specific files.

// Static class variables can be referenced globally, WITHOUT having to use `global` or  `$GLOBALS[]`
//    -- http://stackoverflow.com/questions/834491/create-superglobal-variables-in-php
//
// phpQuery   -- The phpQuery static namespace.
// pq()       -- The phpQuery pq() method; a shortcut to phpQuery::pq().

// SIG Web Components file:
require_once $_SERVER['DOCUMENT_ROOT'] . '/sig_web_components_8.5.0' . '/phpQuery/phpQuery.php';           // OPTIONAL, if you need it

// App-specific files:
require_once 'view/php/app_view.php';   // This is part of your app -- is not part of SIG Web Components.
require_once 'model/app_model.php';     // For now, just to get the system configuration

// Database Connection
require_once 'model/postgres.php';

// DEBUG
if (true) {
   $log->set_enable(true);   // Turning on logging can slow down the app A LOT, especially if you do lots of logging.

   //$_REQUEST['debug_client'] = true;   // Force-hack for testing call below
   //$log->http_request();
}

// Our PHP 5.3 has a default memory limit of 128M.
// Set memory usage limit higher than PHP's default:
//ini_set('memory_limit', '1G');   // Or you could use 1024M



//-----------------------------------------------------------------------------
// Routing
//
// Routes all incoming parent app HTTP and XHR requests -- a .conf file is set to route ALL requests to this index.php.
// Plug-in HTTP page requests also come through here, but plug-in AJAX requests go directly to the plug-in URLs.
//
// Unless you have a very simple app, use this file to handle high-level routing only, and process any URL query
// parameters in your app-specific controller functions.


// For apps using plug-ins:
$m = new app_model();
$system_config = $m->get_system_config();          // App-specific code to get this from the sig_system_mgr table, for example.

/*
try {
   $plugins = $router->get_plugins($system_config);   // Returns plugins (if any) for this app, system_config, and URL.
}
catch (Exception $e) {
   $log->fatal('Exception calling get_plugins(): ' . $e->getMessage());
}
*/


// Route requests
switch (true)
{
   //----------------------
   // Plugin Page requests
   //----------------------

   // Use when the plugin has an URL, and is to be inserted into the common page layout for the app
 
   /*
   case $plugins['page_plugin']:                                  // If has content, a plugin exists for this app, system_config, and URL

      try {
         $v    = new app_view();                                     // Belongs to the app
         $html = $v->get_page_common($remove_unused_macros=false);   // Get the app page for the current URL
      }
      catch (Exception $e) {
         $log->fatal('Exception calling get_plage_common(): ' . $e->getMessage());
      }

      try {
         $html = $router->add_plugins($html, $plugins);              // Passing the HTML; adds plugins to it.
      }
      catch (Exception $e) {
         $log->fatal('Exception calling add_plugins() for the page plug-in: ' . $e->getMessage());
      }

      // Do here: Any remaining app-specific things to the HTML before emitting it, e.g., template fix-ups or app-specific styling overrides. 

      $replace = array('app_full_url' => $app_full_url);
      $html = $swc_view->template_replace_assoc($replace, $html);
      
      // Do elsewhere: Any updates to the app's nav system for Page plug-ins should be done in the app's app_view.php, 
      // in get_page_common() so that the updated navigation is correct for ALL app pages, not only the plugged-in one(s).

      $router->emit_page($html);                                  // PHP script exits here
   */

   //--------------
   // Page requests
   //--------------
   case $router->get("/"):   // Or $router->get("") -- both will work for URLs host/may_app and host/my_app/

      $log->debug('----- New request: home page -----');

      $v    = new app_view();
      //$html = $v->get_home_page($plugins);
      $html = $v->get_home_page();

      $log->debug('Home page PHP seconds = ' . (string)$router->server_seconds());

      $router->emit_page($html);
      break;

   //----------------
   // AJAX requests
   //----------------
   case $router->post("/get_pdo_info"):

      $log->debug('Entered get_pdo_info handler');

      // The app_model was included above and instantiated as $m.

      $html  = $m->get_pdo_keys();
      $html .= $m->get_last_connected_client();

      $json = array('html' => $html);

      $router->emit_json($json);
      break;
   
    case $router->any("/functions"):    // $.ajax( {"url":"functions", "method":"POST, "data": {"func": "add",  ...}} )

      $log->debug('----- New request: ' . $_REQUEST['func'] . ' -----');

      // Using any() to handle both GET and POST
      try {
         require_once 'model/functions.php';

         // Class_name::static_function_name. Params are passed in $_REQUEST / $_GET / $_POST
         $json = call_user_func('Functions::' . $_REQUEST['func']);   // E.g., static function my_func() {...}
      }
      catch (Exception $e) {

         // These are PROGRAM errors rather than user errors. Can log them here.
         $json = array("Exception" => $e);
         $router->set_response_header(http_status::INTERNAL_SERVER_ERROR);
      }

      $log->debug($_REQUEST['func'] . ' PHP seconds = ' . (string)$router->server_seconds());

      $router->emit_json($json);
      break;


   //----------------
   // File downloads
   //----------------
   /*
   case $router->get('/download_static_file'):         // Example static file download; you determine what the URL should be

      $file_name = $GLOBALS['request']['filename'];    // You determine what the param name should be

      $router->emit_static_file($file_name);
      break;

   case $router->get('/download_dynamic_file'):        // Example dynamically-created-file download; you determine what the URL should be

      $file_name = $GLOBALS['request']['filename'];    // You determine what the param name should be

      $file_content = "This is a dynamically-generated demo file.";

      $router->emit_dynamic_file($file_name, $file_content);
      break;
   */
   default:
      // Program error -- Client requested a resource that does not exist.

      $swc_view->send_not_found_page();   // Handles HTTP and AJAX requests
      break;

}  // switch
