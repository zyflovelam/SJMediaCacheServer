//
//  MCSDatabase.h
//  SJMediaCacheServer
//
//  Created by BD on 2021/3/20.
//

#import <Foundation/Foundation.h>
#import <SJSQLite3/SJSQLite3.h>
#import <SJSQLite3/SJSQLite3+QueryExtended.h>
#import <SJSQLite3/SJSQLite3+RemoveExtended.h>
#import <SJSQLite3/SJSQLite3+Private.h>
#import <SJSQLite3/SJSQLite3+FoundationExtended.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT SJSQLite3 *
MCSDatabase(void);
NS_ASSUME_NONNULL_END
