import Foundation

public enum MerchantEngagementSyntheticFixtures {
    public static let access = ##"{"active":true,"merchant":{"id":710,"name":"Synthetic outreach workshop"},"roleCode":"MERCHANT_OWNER","canManageOperators":true,"permissions":["merchant:crm:read","merchant:crm:segment","merchant:crm:export","merchant:crm:sensitive:read","merchant:marketing:write","merchant:coupon:manage","merchant:operator:manage","merchant:aftercare:read","merchant:aftercare:evidence"]}"##
    public static let segments = ##"[{"id":71001,"name":"Example return visitors","filter":{"segment":"repeat","tagId":null,"sourceType":1,"sourceStart":"2026-09-01","sourceEnd":"2026-10-01"}}]"##
    public static let coupons = ##"[{"id":72001,"name":"Example coupon"}]"##
    public static let campaign = ##"{"id":73001,"title":"Example campaign","channel":"IN_APP","status":"READY","recipientCount":4,"deliveredCount":0,"noConsentCount":2,"frequencySkippedCount":1,"failedCount":0,"retryableCount":0,"recipients":[{"recipientId":73011,"customerName":"Synthetic customer","status":"PENDING","failureCode":"","failureMessage":""}]}"##
    public static let audience = ##"{"totalCount":7,"recipientLimit":200,"consentedCount":5,"frequencyLimitedCount":1,"deliverableCount":4}"##
    public static let broadcast = ##"{"audienceCount":7,"consentedCount":5,"noConsentCount":2,"frequencyLimitedCount":1,"deliverableCount":4,"recipientLimit":200,"merchantDailyLimit":1000,"merchantDailyUsed":4,"merchantDailyRemaining":996,"filterTotalCount":7}"##
    public static let exportTask = ##"{"id":74001,"status":"SUCCESS","rowCount":7}"##
    public static let workbookBytes = Data(base64Encoded: "UEsDBBQAAAAIAAAAQl1bma6u5QAAAAsCAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbK2RvVLDMBCEX0WjNhOdk4KCsZ0i0AYKXuCQz7HG+hudEszbIzuBggnQUN1Iu3vfalTvJmfFmRKb4Bu5UZXctfXLeyQWRfHcyCHneA/AeiCHrEIkX5Q+JIe5HNMRIuoRjwTbqroDHXwmn9d53iHb+oF6PNksHqdyfaEksizF/mKcWY3EGK3RmIsOZ999o6yvBFWSi4cHE3lVDBJuEmblZ8A191SenUxH4hlTPqArLpgsvIU0voYwqt+X3GgZ+t5o6oI+uRJRHBNhxwNRdlYtUzk0fvU3fzEzLGPzz0W+9n/2gOW72w9QSwMEFAAAAAgAAABCXUuDozqWAAAABQEAAAsAAABfcmVscy8ucmVsc43PPQ7CMAwF4KtEPkDdMjCgpl1YuiIuEFL3R23iyAlQbk9GihgY/fz0Wa7bza3qQRJn9hqqooS2qS+0mpSDOM0hqtzwUcOUUjghRjuRM7HgQD5vBhZnUh5lxGDsYkbCQ1keUT4N2Juq6zVI11egrq9A/9g8DLOlM9u7I59+nPhqZNnISEnDtuKTZbkxL0VGAZsadw82b1BLAwQUAAAACAAAAEJd6pBlrK0AAAANAQAADwAAAHhsL3dvcmtib29rLnhtbI2POw7CMAyGrxL5AKQwMFR9LCzMnCCkLonaxJXt8rg9EdCdybZ+67O/pn+m2dyRJVJuYb+roO+aB/F0JZpMCbO0EFSX2lrxAZOTHS2YSzISJ6dl5JuVhdENEhA1zfZQVUebXMzwJdT8D4PGMXo8kV8TZv1CGGen5TUJcRHoms8F+VWTXcIWLq+sATV6U8ATDsavopSKE5jP3nkoZmC4jqXh87AH2zV2Q9nNtnsDUEsDBBQAAAAIAAAAQl1tNul0mgAAAAYBAAAaAAAAeGwvX3JlbHMvd29ya2Jvb2sueG1sLnJlbHONzzsOwjAMBuCrRD5A3TIwoKZdWFgRF4hSt6naPBSb1+2JGBCVGJgs/7Y+y23/8Ku6UeY5Bg1NVUPftWdajZSA3ZxYlY3AGpxIOiCydeQNVzFRKJMxZm+ktHnCZOxiJsJdXe8xfxuwNdVp0JBPQwPq8kz0jx3HcbZ0jPbqKciPE3iPeWFHJAU1eSLR8IkY36WpigrYtbj5sHsBUEsDBBQAAAAIAAAAQl0umTrkJgEAAKsEAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sjdRLbsMgEIDhqyAvvQgYv6IKE6Vql13lBMihtRUDFtAmvX1JVI2qCpB3Zka/+Vaww00t6EtaNxs9FNWOFAfOrsZe3CSlR2Gr3VBM3q9PGLtxkkq4nVmlDpt3Y5Xw4Wg/sFutFOdHpBZMCemwErMuOHvMXoQXnFlzRTbcEqbj/eNYFcgPxayXWcuTt2E+O848P31rP0k/j0gLJRn2nOH7Bo+/5XOqfBPuIs9onYz+1+FwOxAoEGjiR683odZFovHTeaOkRVWMkaopoWVZkopUGUQNiHorgsYQqRoQNINoANFsRdQxRKoGRJ1BtIBotyKaGCJVA6LJIDpAdFsRbQyRqgHRZhA9IPqtiC6GSNWA6DKIPSD2WxF9DJGqAdHHEPjPi4HhKeI/UEsBAhQDFAAAAAgAAABCXVuZrq7lAAAACwIAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAAAEJdS4OjOpYAAAAFAQAACwAAAAAAAAAAAAAAgAEWAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACAAAAEJd6pBlrK0AAAANAQAADwAAAAAAAAAAAAAAgAHVAQAAeGwvd29ya2Jvb2sueG1sUEsBAhQDFAAAAAgAAABCXW026XSaAAAABgEAABoAAAAAAAAAAAAAAIABrwIAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzUEsBAhQDFAAAAAgAAABCXS6ZOuQmAQAAqwQAABgAAAAAAAAAAAAAAIABgQMAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAABQAFAEUBAADdBAAAAAA=")!
    public static func decode(_ raw: String) throws -> MerchantBusinessValue { try JSONDecoder().decode(MerchantBusinessValue.self, from: Data(raw.utf8)) }
    public static func payload(_ query: MerchantEngagementQuery) throws -> MerchantEngagementPayload {
        let value: MerchantBusinessValue
        switch query {
        case .segments: value = try decode(segments)
        case .coupons: value = try decode(coupons)
        case .campaigns: value = .array([try decode(campaign)])
        case .campaign: value = try decode(campaign)
        case .campaignPreview: value = try decode(audience)
        case .broadcastPreview: value = try decode(broadcast)
        case .exportStatus: value = try decode(exportTask)
        case .customer: value = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer)
        }
        return try .init(query: query, value: value)
    }
}
