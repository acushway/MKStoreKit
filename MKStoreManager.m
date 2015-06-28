//
//  MKStoreManager.m
//  MKStoreKit (Version 5.0)
//
//	File created using Singleton XCode Template by Mugunth Kumar (http://mugunthkumar.com
//  Permission granted to do anything, commercial/non-commercial with this file apart from removing the line/URL above
//  Read my blog post at http://mk.sg/1m on how to use this code

//  Created by Mugunth Kumar (@mugunthkumar) on 04/07/11.
//  Copyright (C) 2011-2020 by Steinlogic Consulting And Training Pte Ltd.

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

//  As a side note on using this code, you might consider giving some credit to me by
//	1) linking my website from your app's website
//	2) or crediting me inside the app's credits page
//	3) or a tweet mentioning @mugunthkumar
//	4) A paypal donation to mugunth.kumar@gmail.com


#import "MKStoreManager.h"
#import "SFHFKeychainUtils.h"
#import "MKSKProduct.h"
#import "NSData+MKBase64.h"

@interface MKStoreManager () //private methods and properties

@property (nonatomic, copy) void (^onTransactionCancelled)();
@property (nonatomic, copy) void (^onBuyError)();
@property (nonatomic, copy) void (^onTransactionCompleted)(NSString *productId, NSData* receiptData, NSArray* downloads);
@property (nonatomic, copy) void (^onDeferred)();

@property (nonatomic, copy) void (^onRestoreFailed)(NSError* error);
@property (nonatomic, copy) void (^onRestoreCompleted)();

@property (nonatomic, assign, getter=isProductsAvailable) BOOL isProductsAvailable;

@property (nonatomic, strong) SKProductsRequest *productsRequest;

- (void)requestProductData;
- (void)rememberPurchaseOfProduct:(NSString*) productIdentifier withReceipt:(NSData*) receiptData;
- (void)addToQueue:(NSString*) productId;
@end

@implementation MKStoreManager

static MKStoreManager* _sharedStoreManager;

+ (void)updateFromiCloud:(NSNotification*) notificationObject
{

    NSLog(@"Updating from iCloud");

    NSUbiquitousKeyValueStore *iCloudStore = [NSUbiquitousKeyValueStore defaultStore];
    NSDictionary *dict = [iCloudStore dictionaryRepresentation];
    NSMutableArray *products = [self allProducts];

    [products enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {

        id valueFromiCloud = [dict objectForKey:obj];

        if(valueFromiCloud) {
            NSError *error = nil;
            [SFHFKeychainUtils storeUsername:obj
                                 andPassword:valueFromiCloud
                              forServiceName:@"MKStoreKit"
                              updateExisting:YES
                                       error:&error];
            if(error) NSLog(@"%@", error);
        }
    }];
}

+ (BOOL)iCloudAvailable
{

    if(NSClassFromString(@"NSUbiquitousKeyValueStore")) { // is iOS 5?

        if([NSUbiquitousKeyValueStore defaultStore]) {  // is iCloud enabled

            return YES;
        }
    }

    return NO;
}

+ (void)setObject:(id)object forKey:(NSString*)key
{
    if (object) {
        NSString *objectString = nil;
        if([object isKindOfClass:[NSData class]])
        {
            objectString = [[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding];
        }
        if([object isKindOfClass:[NSNumber class]])
        {
            objectString = [(NSNumber*)object stringValue];
        }

        NSError *error = nil;
        [SFHFKeychainUtils storeUsername:key andPassword:objectString forServiceName:@"MKStoreKit" updateExisting:YES error:&error];
        if(error) NSLog(@"%@", error);

        if([self iCloudAvailable]) {
            [[NSUbiquitousKeyValueStore defaultStore] setObject:objectString forKey:key];
            [[NSUbiquitousKeyValueStore defaultStore] synchronize];
        }
    } else {

        NSError *error = nil;
        [SFHFKeychainUtils deleteItemForUsername:key andServiceName:@"MKStoreKit" error:&error];
        if(error) NSLog(@"%@", error);

        if([self iCloudAvailable]) {
            [[NSUbiquitousKeyValueStore defaultStore] removeObjectForKey:key];
            [[NSUbiquitousKeyValueStore defaultStore] synchronize];
        }
    }
}

+ (id)receiptForKey:(NSString*)key
{

    NSData *receipt = [MKStoreManager objectForKey:key];
    if(!receipt)
        receipt = [MKStoreManager objectForKey:[NSString stringWithFormat:@"%@-receipt", key]];

    return receipt;
}

+ (id)objectForKey:(NSString*)key
{
    NSError *error = nil;
    id password = [SFHFKeychainUtils getPasswordForUsername:key andServiceName:@"MKStoreKit" error:&error];
    if(error) NSLog(@"%@", error);

    return password;
}

+ (NSNumber*)numberForKey:(NSString*)key
{
    return [NSNumber numberWithInt:[[MKStoreManager objectForKey:key] intValue]];
}

+ (NSData*)dataForKey:(NSString*)key
{
    NSString *str = [MKStoreManager objectForKey:key];
    return [str dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark Singleton Methods

+ (MKStoreManager*)sharedManager
{
    if(!_sharedStoreManager) {
        static dispatch_once_t oncePredicate;
        dispatch_once(&oncePredicate, ^{
            _sharedStoreManager = [[self alloc] init];
            _sharedStoreManager.purchasableObjects = [NSMutableArray array];
            [_sharedStoreManager requestProductData];
            [[SKPaymentQueue defaultQueue] addTransactionObserver:_sharedStoreManager];
        });

        if([self iCloudAvailable])
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(updateFromiCloud:)
                                                         name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                                                       object:nil];


    }
    return _sharedStoreManager;
}

#pragma mark Internal MKStoreKit functions

+ (NSDictionary*)storeKitItems
{
    return [NSDictionary dictionaryWithContentsOfFile:
            [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:
             @"MKStoreKitConfigs.plist"]];
}

- (void)restorePreviousTransactionsOnComplete:(void (^)(void)) completionBlock
                                      onError:(void (^)(NSError*)) errorBlock
{
    self.onRestoreCompleted = completionBlock;
    self.onRestoreFailed = errorBlock;

    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)restoreCompleted
{
    if (self.onRestoreCompleted) {
        self.onRestoreCompleted();
    }
    self.onRestoreCompleted = nil;
}

- (void)restoreFailedWithError:(NSError*)error
{
    if (self.onRestoreFailed) {
        self.onRestoreFailed(error);
    }
    self.onRestoreFailed = nil;
}

- (void)requestProductData
{
    NSMutableArray *productsArray = [NSMutableArray array];
    NSArray *consumables = [[[MKStoreManager storeKitItems] objectForKey:@"Consumables"] allKeys];
    NSArray *nonConsumables = [[MKStoreManager storeKitItems] objectForKey:@"Non-Consumables"];

    [productsArray addObjectsFromArray:consumables];
    [productsArray addObjectsFromArray:nonConsumables];

    self.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productsArray]];
    self.productsRequest.delegate = self;
    [self.productsRequest start];
}

+ (NSMutableArray*)allProducts
{
    NSMutableArray *productsArray = [NSMutableArray array];
    NSArray *consumables = [[[self storeKitItems] objectForKey:@"Consumables"] allKeys];
    NSArray *consumableNames = [self allConsumableNames];
    NSArray *nonConsumables = [[self storeKitItems] objectForKey:@"Non-Consumables"];

    [productsArray addObjectsFromArray:consumables];
    [productsArray addObjectsFromArray:consumableNames];
    [productsArray addObjectsFromArray:nonConsumables];

    return productsArray;
}

+ (NSArray *)allConsumableNames
{
    NSMutableSet *consumableNames = [[NSMutableSet alloc] initWithCapacity:0];
    NSDictionary *consumables = [[self storeKitItems] objectForKey:@"Consumables"];
    for (NSDictionary *consumable in [consumables allValues]) {
        NSString *name = [consumable objectForKey:@"Name"];
        [consumableNames addObject:name];
    }

    return [consumableNames allObjects];
}

- (BOOL)removeAllKeychainData
{
    NSMutableArray *productsArray = [MKStoreManager allProducts];
    NSInteger itemCount = productsArray.count;
    NSError *error;

    //loop through all the saved keychain data and remove it
    for (int i = 0; i < itemCount; i++ ) {
        [SFHFKeychainUtils deleteItemForUsername:[productsArray objectAtIndex:i] andServiceName:@"MKStoreKit" error:&error];
    }
    if (!error) {
        return YES;
    } else {
        return NO;
    }
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    [self.purchasableObjects addObjectsFromArray:response.products];

#ifdef DEBUG
    for(int i=0;i<[self.purchasableObjects count];i++) {
        SKProduct *product = [self.purchasableObjects objectAtIndex:i];
        NSLog(@"Feature: %@, Cost: %f, ID: %@",[product localizedTitle],
              [[product price] doubleValue], [product productIdentifier]);
    }

    for(NSString *invalidProduct in response.invalidProductIdentifiers) {
        NSLog(@"Problem in iTunes connect configuration for product: %@", invalidProduct);
    }
#endif

    self.isProductsAvailable = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:kProductFetchedNotification
                                                        object:[NSNumber numberWithBool:self.isProductsAvailable]];
    self.productsRequest = nil;
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    self.isProductsAvailable = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:kProductFetchedNotification
                                                        object:[NSNumber numberWithBool:self.isProductsAvailable]];
    self.productsRequest = nil;
}

// call this function to check if the user has already purchased your feature
+ (BOOL)isFeaturePurchased:(NSString*)featureId
{
    return [[MKStoreManager numberForKey:featureId] boolValue];
}

// Call this function to populate your UI
// this function automatically formats the currency based on the user's locale

- (NSMutableArray*)purchasableObjectsDescription
{
    NSMutableArray *productDescriptions = [[NSMutableArray alloc] initWithCapacity:[self.purchasableObjects count]];
    for(int i=0;i<[self.purchasableObjects count];i++)
    {
        SKProduct *product = [self.purchasableObjects objectAtIndex:i];

        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
        [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        [numberFormatter setLocale:product.priceLocale];
        NSString *formattedString = [numberFormatter stringFromNumber:product.price];

        // you might probably need to change this line to suit your UI needs
        NSString *description = [NSString stringWithFormat:@"%@ (%@)",[product localizedTitle], formattedString];

#ifdef DEBUG
        NSLog(@"Product %d - %@", i, description);
#endif
        [productDescriptions addObject: description];
    }

    return productDescriptions;
}

/*Call this function to get a dictionary with all prices of all your product identifers

 For example,

 NSDictionary *prices = [[MKStoreManager sharedManager] pricesDictionary];

 NSString *upgradePrice = [prices objectForKey:@"com.mycompany.upgrade"]

 */
- (NSMutableDictionary *)pricesDictionary
{
    NSMutableDictionary *priceDict = [NSMutableDictionary dictionary];
    for(int i=0;i<[self.purchasableObjects count];i++) {
        SKProduct *product = [self.purchasableObjects objectAtIndex:i];

        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
        [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        [numberFormatter setLocale:product.priceLocale];
        NSString *formattedString = [numberFormatter stringFromNumber:product.price];

        NSString *priceString = [NSString stringWithFormat:@"%@", formattedString];
        [priceDict setObject:priceString forKey:product.productIdentifier];

    }
    return priceDict;
}

- (void)showAlertWithTitle:(NSString*) title message:(NSString*) message
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"Dismiss", @"")
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)buyFeature:(NSString*) featureId
        onComplete:(void (^)(NSString*, NSData*, NSArray*)) completionBlock
       onCancelled:(void (^)(void)) cancelBlock
{
    [self buyFeature:featureId onComplete:completionBlock onCancelled:cancelBlock onDeferred:nil onError:nil];
}

- (void)buyFeature:(NSString*) featureId
        onComplete:(void (^)(NSString* purchasedFeature, NSData*purchasedReceipt, NSArray* availableDownloads)) completionBlock
       onCancelled:(void (^)(void)) cancelBlock
        onDeferred:(void (^)(void)) deferredBlock
           onError:(void (^)(void)) errorBlock
{
    self.onTransactionCompleted = completionBlock;
    self.onTransactionCancelled = cancelBlock;
    self.onDeferred = deferredBlock;
    self.onBuyError = errorBlock;

    [self addToQueue:featureId];
}

-(void) addToQueue:(NSString*) productId
{
    if ([SKPaymentQueue canMakePayments]) {
        NSArray *allIds = [self.purchasableObjects valueForKey:@"productIdentifier"];
        NSInteger index = [allIds indexOfObject:productId];

        if(index == NSNotFound) {
            if (self.onBuyError) {
                self.onBuyError();
                self.onBuyError = nil;
            }
            return;
        }

        SKProduct *thisProduct = [self.purchasableObjects objectAtIndex:index];
        SKPayment *payment = [SKPayment paymentWithProduct:thisProduct];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    } else {
        [self showAlertWithTitle:NSLocalizedString(@"In-App Purchasing disabled", @"")
                         message:NSLocalizedString(@"Check your parental control settings and try again later", @"")];
    }
}

- (BOOL)canConsumeProduct:(NSString*) productIdentifier
{
    int count = [[MKStoreManager numberForKey:productIdentifier] intValue];

    return (count > 0);

}

- (BOOL)canConsumeProduct:(NSString*) productIdentifier quantity:(int) quantity
{
    int count = [[MKStoreManager numberForKey:productIdentifier] intValue];
    return (count >= quantity);
}

- (BOOL)consumeProduct:(NSString*) productIdentifier quantity:(int) quantity
{
    int count = [[MKStoreManager numberForKey:productIdentifier] intValue];
    if(count < quantity) {
        return NO;
    } else {
        count -= quantity;
        [MKStoreManager setObject:[NSNumber numberWithInt:count] forKey:productIdentifier];
        return YES;
    }
}

#pragma mark In-App purchases callbacks
// In most cases you don't have to touch these methods
- (void)provideContent: (NSString*) productIdentifier
            forReceipt:(NSData*) receiptData
         hostedContent:(NSArray*) hostedContent
{
    if(!receiptData) {
        if(self.onTransactionCancelled) {
            self.onTransactionCancelled(productIdentifier);
        } else {
            NSLog(@"Receipt invalid");
        }
    }

    [self rememberPurchaseOfProduct:productIdentifier withReceipt:receiptData];
    if(self.onTransactionCompleted) {
        self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
    }
}

- (void)rememberPurchaseOfProduct:(NSString*) productIdentifier withReceipt:(NSData*) receiptData
{
    NSDictionary *allConsumables = [[MKStoreManager storeKitItems] objectForKey:@"Consumables"];
    if([[allConsumables allKeys] containsObject:productIdentifier]) {
        NSDictionary *thisConsumableDict = [allConsumables objectForKey:productIdentifier];
        int quantityPurchased = [[thisConsumableDict objectForKey:@"Count"] intValue];
        NSString* productPurchased = [thisConsumableDict objectForKey:@"Name"];

        int oldCount = [[MKStoreManager numberForKey:productPurchased] intValue];
        int newCount = oldCount + quantityPurchased;

        [MKStoreManager setObject:[NSNumber numberWithInt:newCount] forKey:productPurchased];
    } else {
        [MKStoreManager setObject:[NSNumber numberWithBool:YES] forKey:productIdentifier];
    }

    [MKStoreManager setObject:receiptData forKey:[NSString stringWithFormat:@"%@-receipt", productIdentifier]];
}

#pragma -
#pragma mark Store Observer

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;

            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;

            case SKPaymentTransactionStateRestored:
                [self restoreTransaction:transaction];
                break;

            case SKPaymentTransactionStateDeferred:
                if (self.onDeferred) {
                    self.onDeferred();
                    self.onDeferred = nil;
                }
                break;

            default:
                break;
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    [self restoreFailedWithError:error];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    [self restoreCompleted];
}

- (void)failedTransaction: (SKPaymentTransaction *)transaction
{
#ifdef DEBUG
    NSLog(@"Failed transaction: %@", [transaction description]);
    NSLog(@"error: %@", transaction.error);
#endif

    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];

    if(self.onTransactionCancelled) {
        self.onTransactionCancelled();
    }
}

- (void)completeTransaction: (SKPaymentTransaction *)transaction
{
    NSArray *downloads = nil;

    if([transaction respondsToSelector:@selector(downloads)]) {
        downloads = transaction.downloads;
    }

    if([downloads count] > 0) {

        [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
        // We don't have content yet, and we can't finish the transaction
#ifdef DEBUG
        NSLog(@"Download(s) started: %@", [transaction description]);
#endif
        return;
    }

    [self provideContent:transaction.payment.productIdentifier
              forReceipt:transaction.transactionReceipt
           hostedContent:downloads];

    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)restoreTransaction: (SKPaymentTransaction *)transaction
{
    NSArray *downloads = nil;

    if([transaction respondsToSelector:@selector(downloads)]) {
        downloads = transaction.downloads;
    }
    if([downloads count] > 0) {
        [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
        // We don't have content yet, and we can't finish the transaction
#ifdef DEBUG
        NSLog(@"Download(s) started: %@", [transaction description]);
#endif
        return;
    }

    [self provideContent: transaction.originalTransaction.payment.productIdentifier
              forReceipt:transaction.transactionReceipt
           hostedContent:downloads];
    
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
}

@end
