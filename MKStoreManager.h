//
//  MKStoreManager.h
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

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import "MKStoreKitConfigs.h"

#define kProductFetchedNotification @"MKStoreKitProductsFetched"

@interface MKStoreManager : NSObject<SKProductsRequestDelegate, SKPaymentTransactionObserver>

// These are the methods you will be using in your app
+ (MKStoreManager*)sharedManager;

// this is a class method, since it doesn't require the store manager to be initialized prior to calling
+ (BOOL) isFeaturePurchased:(NSString*) featureId;

@property (nonatomic, strong) NSMutableArray *purchasableObjects;
// convenience methods
//returns a dictionary with all prices for identifiers
- (NSMutableDictionary *)pricesDictionary;
- (NSMutableArray*) purchasableObjectsDescription;

// use this method to start a purchase
- (void) buyFeature:(NSString*) featureId
         onComplete:(void (^)(NSString* purchasedFeature, NSArray* availableDownloads)) completionBlock
        onCancelled:(void (^)(void)) cancelBlock;

// use this method to start a purchase
- (void) buyFeature:(NSString*) featureId
         onComplete:(void (^)(NSString* purchasedFeature, NSArray* availableDownloads)) completionBlock
        onCancelled:(void (^)(void)) cancelBlock
        onDeferred:(void (^)(void)) deferredBlock
        onError:(void (^)(void)) errorBlock;

// use this method to restore a purchase
- (void) restorePreviousTransactionsOnComplete:(void (^)(void)) completionBlock
                                       onError:(void (^)(NSError* error)) errorBlock;

// For consumable support
- (BOOL) canConsumeProduct:(NSString*) productName quantity:(int) quantity;
- (BOOL) consumeProduct:(NSString*) productName quantity:(int) quantity;

// for testing proposes you can use this method to remove all the saved keychain data (saved purchases, etc.)
- (BOOL) removeAllKeychainData;

+(void) setObject:(id) object forKey:(NSString*) key;
+(NSNumber*) numberForKey:(NSString*) key;

@end
