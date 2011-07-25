//
//  SCFoursquarePlacePickerController.m
//  Soundcloud
//
//  Created by Gernot Poetsch on 30.11.10.
//  Copyright 2010 nxtbgthng. All rights reserved.
//

#import "NSData+SCKit.h"

#import "GPURLConnection.h"
#import "GPWebAPI.h"

#import "SCConstants.h"

#import "SCFoursquarePlacePickerController.h"

@interface SCFoursquarePlacePickerController ()
@property (nonatomic, retain) NSArray *venues;
- (IBAction)finishWithReset;
@end


@implementation SCFoursquarePlacePickerController

#pragma mark Lifecycle

- (id)initWithDelegate:(id<SCFoursquarePlacePickerControllerDelegate>)aDelegate;
{
    if ((self = [super init])) {
        
        self.title = @"Where?";
        
        delegate = aDelegate;
        
        api = [[GPWebAPI alloc] initWithHost:@"api.foursquare.com" delegate:self];
        api.scheme = @"https";
        api.path = @"v2";
        
        locationManager = [[CLLocationManager alloc] init];
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
        locationManager.distanceFilter = 30.0;
        locationManager.delegate = self;
        if ([locationManager respondsToSelector:@selector(purpose)]) {
//            locationManager.purpose = @"Purpose Test";
        }
        [locationManager startUpdatingLocation];
        
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Reset"
                                                                                   style:UIBarButtonItemStyleBordered
                                                                                  target:self
                                                                                  action:@selector(finishWithReset)] autorelease];
    }
    return self;
}

- (void)dealloc;
{
    [locationManager stopUpdatingLocation];
    [locationManager release];
    [api release];
    [venues release];
    [venueRequestIdentifier release];
    [super dealloc];
}


#pragma mark Accessors

@synthesize venues;

- (void)setVenues:(NSArray *)value;
{
    [value retain]; [venues release]; venues = value;
    self.tableView.separatorStyle = (venues.count > 0) ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
    [self.tableView reloadData];
}


#pragma mark ViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UIToolbar *customTitleBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 44.0)];
    customTitleBar.tintColor = [UIColor colorWithWhite:0.66 alpha:1.0];
    
    UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0.0, 0.0, 300, 26.0)];
    textField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    textField.placeholder = @"Add Your Place";
    textField.returnKeyType = UIReturnKeyDone;
    textField.keyboardAppearance = UIKeyboardAppearanceAlert;
    textField.borderStyle = UITextBorderStyleRoundedRect;
    textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    textField.delegate = self;
    
    [customTitleBar setItems:[NSArray arrayWithObjects:
                              [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                              [[[UIBarButtonItem alloc] initWithCustomView:textField] autorelease],
                              [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                              nil]];
    
    [textField release];
    
    self.tableView.tableHeaderView = customTitleBar;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [customTitleBar release];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [locationManager startUpdatingLocation];
}

- (void)viewDidAppear:(BOOL)animated;
{
	[super viewDidAppear:animated];
    if (locationManager && locationManager.location) {
        [self locationManager:locationManager didUpdateToLocation:locationManager.location fromLocation:nil];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}


#pragma mark TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return venues.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"venueCell"];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"venueCell"] autorelease];
    }
    NSDictionary *venue = [self.venues objectAtIndex:indexPath.row];
    cell.textLabel.text = [venue objectForKey:@"name"];
    cell.detailTextLabel.text = [[venue objectForKey:@"location"] objectForKey:@"address"];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    return @"Nearby";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSDictionary *venue = [self.venues objectAtIndex:indexPath.row];
    [delegate foursquarePlacePicker:self
                 didFinishWithTitle:[venue objectForKey:@"name"]
                       foursquareID:([venue objectForKey:@"id"]) ? [NSString stringWithFormat:@"%@", [venue objectForKey:@"id"]] : nil //it might be a number
                           location:locationManager.location];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


#pragma mark Location delegate

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation;
{
    [api cancelRequest:venueRequestIdentifier];
    [venueRequestIdentifier release];
    
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSString stringWithFormat:@"%f,%f", newLocation.coordinate.latitude, newLocation.coordinate.longitude], @"ll",
                               [NSString stringWithFormat:@"%f", newLocation.horizontalAccuracy], @"llAcc",
                               [NSString stringWithFormat:@"%.0f", newLocation.altitude], @"alt",
                               @"50", @"limit", 
                               SCFoursquareKey, @"client_id",
                               SCFoursquareSecret, @"client_secret",
                               @"20110622", @"v",
                               nil];
    
    venueRequestIdentifier = [[api getResource:@"venues/search"
                                 withArguments:arguments] retain];
    
    NSTimeInterval age = -[newLocation.timestamp timeIntervalSinceNow];
    
    if (age < 60.0 //if it is not older than a minute
        && newLocation.horizontalAccuracy <= 50.0) { //and more precise than 5app0 meters
        [manager stopUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error;
{
	NSLog(@"locationManager:didFailWithError: %@", error);
}

#pragma mark Api Delegate

- (void)webApi:(GPWebAPI *)api didFinishWithData:(NSData *)data userInfo:(id)userInfo context:(id)context;
{
	id results = [data JSONObject];
    
    if (![results isKindOfClass:[NSDictionary class]]) return;
    
    self.venues = [[results objectForKey:@"response"] objectForKey:@"venues"];
}

- (void)webApi:(GPWebAPI *)aApi didFailWithError:(NSError *)error data:(NSData *)data userInfo:(id)userInfo context:(id)context;
{
    NSLog(@"Location Request for api %@ failed: %@", aApi, error);
}


#pragma mark TextField

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    [delegate foursquarePlacePicker:self
                 didFinishWithTitle:textField.text
                       foursquareID:nil
                           location:nil];
    return NO;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField;
{
    [textField performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0];
    return YES;
}

#pragma mark Actions

- (IBAction)finishWithReset;
{
    [delegate foursquarePlacePicker:self
                 didFinishWithTitle:nil
                       foursquareID:nil
                           location:nil];
}

@end
