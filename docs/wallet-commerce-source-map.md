# Source map

| Source surface / model | Native files / entry | Exact contract and boundary |
|---|---|---|
| `feature/assets/assets_page.dart`, `data/api/asset_api.dart`, `models/funds_stages.dart` | WalletAssetsView, WalletFundsStages, WalletCommerceService.stages | POST `/api/wallet/stages`, empty JSON `{}`; all required stage fields valid or block unavailable; amountsKnown caveat; independent ledger failures |
| `data/models/asset_record.dart` | WalletLedgerRow + WalletLedgerView(.balance/.assetPoints) | POST `/api/balance/list` and `/api/points/list`; multipart; `data` array; balance optional `change_type`; no fake server pagination |
| `feature/account/income_detail_page.dart`, `registration_api.dart:314`, `models/balance_detail.dart` | WalletIncomeView; WalletLedgerPager | POST `/api/user/balance/list`; `eventType` absent/all, `1` creation, `2` brand; `pageNum/pageSize`; data.rows/total; Club -> existing coop finance |
| `feature/points/points_controller.dart`, `points_api.dart`, `models/points_record.dart` | WalletLedgerView(.points), WalletLedgerPager | POST `/api/user/points/list`; real paging, data.rows with top rows fallback; total numeric/string; local direction tabs; balance from first loaded row afterPoints |
| `feature/points/points_tasks_sheet.dart`, `models/points_task.dart`, `registration_api.dart:368` | WalletPointsTasksView, WalletPointsTask | POST `/api/points/result_list` empty multipart, array; only status=1 and eventType !=14; no grant/claim operation |
| `feature/mall/product_list_page.dart`, `product_detail_page.dart`, `models/product.dart` | WalletProductsView / WalletProductView | POST `/api/product/list` merchant_id>0 optional, sort_type 0...4, optional keyword; data.rows; `/api/product/info` id; points-valued prices, nullable stock, SKU details |
| `feature/mall/cart_page.dart`, `mall_api.dart` | WalletCartView; dormant command builder | `/api/cart/list` empty multipart, data.rows; add `/api/cart/cart/add` product_id/sku_id/quantity/is_buy=0; update `/api/cart/update` cart_id/quantity/sku_id; delete `/api/cart/delete` cartids |
| `feature/mall/cart_checkout_sheet.dart`, `mall_settlement_test.dart` | WalletCheckoutView, WalletCheckoutSnapshot, WalletCommerceReview | `/api/cart/settlement` cartids; productAmount/productQuantity/productWeight/deliveryFee/taxFee/totalAmount/productList/address/pointBalance; ceil total points, unknown != zero |
| `mall_api.dart:settleOrder` | WalletCommerceDormantAdapter | `/api/cart/order/settlement`, cartids/remark/addressid; response data positive integer/string order reference. Closed live gate and durable replay lock |
| `feature/withdrawal/**`, `withdrawal_api.dart`, `models/withdrawal.dart` | WalletWithdrawalsView / WalletWithdrawalRecord | `/api/withdrawal/list` POST without body; array, rows or list; no page params in source wrapper; 0 pending,1 approved,2 paid,3 rejected; masked account |
| `withdrawal_contact_dialog.dart`, R10 comments | Host support surface only | Source explicitly removed create/preflight/bank-transfer UI and methods. No speculative replacement. Source support constant is not copied into this module |

## Source regression references

- `test/data/api/asset_wallet_stages_test.dart`
- `test/data/api/mall_settlement_test.dart`
- `test/data/models/asset_record_sign_test.dart`
- `test/data/models/points_record_sign_test.dart`
- `test/feature/account/income_detail_test.dart`
- `test/feature/assets/assets_stages_test.dart`
- `test/feature/points/points_task_test.dart`
- `test/feature/withdrawal/withdrawal_r10_single_source_test.dart`
- `test/feature/withdrawal/withdrawal_records_refresh_error_test.dart`

These files were source references; their Dart suites were not executed in this isolated Swift addition.
