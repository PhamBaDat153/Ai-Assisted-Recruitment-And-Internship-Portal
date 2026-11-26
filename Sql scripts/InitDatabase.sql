/* =====================================================================
   Cổng Tuyển dụng và Thực tập Hỗ trợ bởi AI
   (AI-Assisted Recruitment and Internship Portal)
   Script khởi tạo cơ sở dữ liệu - Microsoft SQL Server 2019+
   Nguồn: "Database Design - AI-Assisted Recruitment & Internship Portal"
          và ERD.drawio (38 bảng, 66 mối quan hệ)

   Quy ước
   - Khóa chính: UNIQUEIDENTIFIER lưu giá trị UUIDv7 do ứng dụng tạo
     (Guid.CreateVersion7(), .NET 9+). Không đặt DEFAULT cho các cột Id.
     Ngoại lệ: Provinces / Wards (mã INT chính thức từ
     provinces.open-api.vn) và ApplicationStatuses (dữ liệu khởi tạo TINYINT).
   - Các bảng ghi nối có lưu lượng lớn dùng khóa chính NONCLUSTERED kết hợp
     với clustered index trên (khóa ngoại cha, thời gian) vì SQL Server không
     sắp xếp giá trị UUIDv7 theo thứ tự tạo.
   - Mọi mốc thời gian đều là UTC (DATETIME2). Tiền tệ dùng DECIMAL(18,2)
     theo đơn vị VND.
   - Collation của cơ sở dữ liệu là Vietnamese_CI_AI (không phân biệt chữ hoa/thường
     và không phân biệt dấu).

   Chạy một lần trong SSMS / Azure Data Studio / sqlcmd. Chạy lại sẽ xóa
   và tạo lại cơ sở dữ liệu (xem phần DROP) - toàn bộ dữ liệu sẽ bị mất.
   ===================================================================== */

USE master;
GO

IF DB_ID(N'RecruitmentPortal') IS NOT NULL
BEGIN
    ALTER DATABASE RecruitmentPortal SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RecruitmentPortal;
END
GO

CREATE DATABASE RecruitmentPortal COLLATE Vietnamese_CI_AI;
GO

USE RecruitmentPortal;
GO

/* =====================================================================
   7. REFERENCE DATA
   ===================================================================== */

-- Provinces: Tỉnh / thành phố trực thuộc trung ương. Đồng bộ từ provinces.open-api.vn (API v2, sau sáp nhập 07/2025).
CREATE TABLE dbo.Provinces (
    Code            INT            NOT NULL,  -- Mã định danh
    Name            NVARCHAR(100)  NOT NULL,  -- Tên
    Codename        VARCHAR(100)   NOT NULL,  -- Tên không dấu dạng slug (theo API)
    DivisionType    NVARCHAR(50)   NOT NULL,  -- Loại đơn vị hành chính
    PhoneCode       SMALLINT       NULL,  -- Mã vùng điện thoại
    IsActive        BIT            NOT NULL CONSTRAINT DF_Provinces_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    LastSyncedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_Provinces_LastSyncedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm đồng bộ gần nhất từ API (UTC)
    CONSTRAINT PK_Provinces PRIMARY KEY (Code),
    CONSTRAINT UQ_Provinces_Codename UNIQUE (Codename)
);

-- Wards: Phường / xã / đặc khu thuộc một tỉnh (mô hình 2 cấp, không còn cấp huyện). Đồng bộ từ provinces.open-api.vn.
CREATE TABLE dbo.Wards (
    Code            INT            NOT NULL,  -- Mã định danh
    ProvinceCode    INT            NOT NULL,  -- Tỉnh / thành phố chứa phường / xã này
    Name            NVARCHAR(150)  NOT NULL,  -- Tên
    Codename        VARCHAR(150)   NOT NULL,  -- Tên không dấu dạng slug (theo API)
    DivisionType    NVARCHAR(50)   NOT NULL,  -- Loại đơn vị hành chính
    IsActive        BIT            NOT NULL CONSTRAINT DF_Wards_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    LastSyncedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_Wards_LastSyncedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm đồng bộ gần nhất từ API (UTC)
    CONSTRAINT PK_Wards PRIMARY KEY (Code),
    CONSTRAINT FK_Wards_Provinces FOREIGN KEY (ProvinceCode) REFERENCES dbo.Provinces (Code)
);
CREATE INDEX IX_Wards_ProvinceCode ON dbo.Wards (ProvinceCode, IsActive);

-- Industries: Lĩnh vực / ngành nghề kinh doanh, dùng cho công ty và bộ lọc "lĩnh vực" của tin tuyển dụng.
CREATE TABLE dbo.Industries (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    Code            VARCHAR(30)    NOT NULL,  -- Mã định danh
    NameVi          NVARCHAR(150)  NOT NULL,  -- Tên tiếng Việt
    NameEn          NVARCHAR(150)  NOT NULL,  -- Tên tiếng Anh
    IsActive        BIT            NOT NULL CONSTRAINT DF_Industries_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Industries_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_Industries PRIMARY KEY (Id),
    CONSTRAINT UQ_Industries_Code UNIQUE (Code)
);

-- Universities: Danh sách trường đại học / cao đẳng mà sinh viên theo học.
CREATE TABLE dbo.Universities (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    Code            VARCHAR(20)    NOT NULL,  -- Mã định danh
    NameVi          NVARCHAR(255)  NOT NULL,  -- Tên tiếng Việt
    NameEn          NVARCHAR(255)  NULL,  -- Tên tiếng Anh
    ProvinceCode    INT            NULL,  -- Tỉnh / thành phố đặt trường
    IsActive        BIT            NOT NULL CONSTRAINT DF_Universities_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Universities_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_Universities PRIMARY KEY (Id),
    CONSTRAINT UQ_Universities_Code UNIQUE (Code),
    CONSTRAINT FK_Universities_Provinces FOREIGN KEY (ProvinceCode) REFERENCES dbo.Provinces (Code)
);
CREATE INDEX IX_Universities_ProvinceCode ON dbo.Universities (ProvinceCode);

-- Majors: Danh sách ngành học.
CREATE TABLE dbo.Majors (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    Code            VARCHAR(20)    NULL,  -- Mã ngành (theo Bộ GD&ĐT nếu có)
    NameVi          NVARCHAR(200)  NOT NULL,  -- Tên tiếng Việt
    NameEn          NVARCHAR(200)  NULL,  -- Tên tiếng Anh
    IsActive        BIT            NOT NULL CONSTRAINT DF_Majors_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Majors_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_Majors PRIMARY KEY (Id)
);
CREATE UNIQUE INDEX UQ_Majors_Code ON dbo.Majors (Code) WHERE Code IS NOT NULL;

-- Skills: Danh mục kỹ năng chuẩn, dùng chung cho sinh viên, CV, tin tuyển dụng và AI so khớp.
CREATE TABLE dbo.Skills (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    Name            NVARCHAR(100)  NOT NULL,  -- Tên
    NormalizedName  NVARCHAR(100)  NOT NULL,  -- Tên chuẩn hóa (viết hoa) để tránh trùng
    Category        TINYINT        NOT NULL,  -- Nhóm kỹ năng. 1 Technical, 2 Soft, 3 Language, 4 Tool
    IsApproved      BIT            NOT NULL CONSTRAINT DF_Skills_IsApproved DEFAULT (0),  -- Đã được quản trị viên duyệt (kỹ năng AI đề xuất chờ duyệt)
    IsActive        BIT            NOT NULL CONSTRAINT DF_Skills_IsActive DEFAULT (1),  -- Còn sử dụng hay không
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Skills_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_Skills PRIMARY KEY (Id),
    CONSTRAINT UQ_Skills_NormalizedName UNIQUE (NormalizedName),
    CONSTRAINT CK_Skills_Category CHECK (Category BETWEEN 1 AND 4)
);

-- ApplicationStatuses: Các trạng thái của hồ sơ ứng tuyển (phễu tuyển dụng), có thứ tự hiển thị.
CREATE TABLE dbo.ApplicationStatuses (
    Id              TINYINT        NOT NULL,  -- Khóa chính (giá trị cố định)
    Code            VARCHAR(20)    NOT NULL,  -- Mã định danh
    NameVi          NVARCHAR(50)   NOT NULL,  -- Tên tiếng Việt
    NameEn          NVARCHAR(50)   NOT NULL,  -- Tên tiếng Anh
    SortOrder       TINYINT        NOT NULL,  -- Thứ tự trong phễu tuyển dụng
    IsFinal         BIT            NOT NULL,  -- Trạng thái kết thúc phễu (nhà tuyển dụng vẫn có thể mở lại)
    CONSTRAINT PK_ApplicationStatuses PRIMARY KEY (Id),
    CONSTRAINT UQ_ApplicationStatuses_Code UNIQUE (Code)
);
GO

/* =====================================================================
   1. IDENTITY & SYSTEM  (ASP.NET Core Identity with Guid keys, renamed)
   ===================================================================== */

-- Users: Tài khoản đăng nhập của mọi người dùng (sinh viên, nhà tuyển dụng, quản trị viên). Chỉ chứa thông tin xác thực, không chứa hồ sơ.
CREATE TABLE dbo.Users (
    Id                   UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserName             NVARCHAR(256)  NULL,  -- Tên đăng nhập (Identity yêu cầu; đặt bằng Email)
    NormalizedUserName   NVARCHAR(256)  NULL,  -- Tên đăng nhập chuẩn hóa
    Email                NVARCHAR(256)  NOT NULL,  -- Email đăng nhập
    NormalizedEmail      NVARCHAR(256)  NOT NULL,  -- Email chuẩn hóa (viết hoa), duy nhất
    EmailConfirmed       BIT            NOT NULL CONSTRAINT DF_Users_EmailConfirmed DEFAULT (0),  -- Email đã xác nhận
    PasswordHash         NVARCHAR(MAX)  NULL,  -- Mật khẩu đã băm (không bao giờ lưu mật khẩu gốc)
    SecurityStamp        NVARCHAR(MAX)  NULL,  -- Dấu bảo mật, đổi khi đổi mật khẩu (Identity)
    ConcurrencyStamp     NVARCHAR(MAX)  NULL,  -- Dấu chống xung đột cập nhật (Identity)
    PhoneNumber          NVARCHAR(MAX)  NULL,  -- Cột của Identity, không dùng (SĐT nằm trong hồ sơ)
    PhoneNumberConfirmed BIT            NOT NULL CONSTRAINT DF_Users_PhoneNumberConfirmed DEFAULT (0),  -- Cột của Identity, không dùng
    TwoFactorEnabled     BIT            NOT NULL CONSTRAINT DF_Users_TwoFactorEnabled DEFAULT (0),  -- Bật xác thực 2 lớp
    LockoutEnd           DATETIMEOFFSET NULL,  -- Khóa tài khoản đến thời điểm này (sau nhiều lần đăng nhập sai)
    LockoutEnabled       BIT            NOT NULL CONSTRAINT DF_Users_LockoutEnabled DEFAULT (1),  -- Cho phép khóa tài khoản khi đăng nhập sai
    AccessFailedCount    INT            NOT NULL CONSTRAINT DF_Users_AccessFailedCount DEFAULT (0),  -- Số lần đăng nhập sai liên tiếp
    AccountStatus        TINYINT        NOT NULL CONSTRAINT DF_Users_AccountStatus DEFAULT (1),  -- Trạng thái tài khoản. 0 PendingRoleSelection, 1 Active, 2 Suspended, 3 Deactivated
    LastLoginAt          DATETIME2(0)   NULL,  -- Lần đăng nhập gần nhất (UTC)
    CreatedAt            DATETIME2(0)   NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt            DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    DeletedAt            DATETIME2(0)   NULL,  -- Thời điểm ẩn danh hóa tài khoản; NULL = đang dùng
    CONSTRAINT PK_Users PRIMARY KEY (Id),
    CONSTRAINT UQ_Users_NormalizedEmail UNIQUE (NormalizedEmail),
    CONSTRAINT CK_Users_AccountStatus CHECK (AccountStatus BETWEEN 0 AND 3)
);
CREATE UNIQUE INDEX UQ_Users_NormalizedUserName ON dbo.Users (NormalizedUserName) WHERE NormalizedUserName IS NOT NULL;

-- Roles: Các vai trò trong hệ thống: Admin, Employer, Student.
CREATE TABLE dbo.Roles (
    Id               UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    Name             NVARCHAR(256)  NOT NULL,  -- Tên vai trò
    NormalizedName   NVARCHAR(256)  NOT NULL,  -- Tên vai trò chuẩn hóa, duy nhất
    ConcurrencyStamp NVARCHAR(MAX)  NULL,  -- Dấu chống xung đột cập nhật (Identity)
    CONSTRAINT PK_Roles PRIMARY KEY (Id),
    CONSTRAINT UQ_Roles_NormalizedName UNIQUE (NormalizedName)
);

-- UserRoles: Bảng trung gian gán vai trò cho tài khoản (bắt buộc theo ASP.NET Core Identity).
CREATE TABLE dbo.UserRoles (
    UserId  UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản liên quan
    RoleId  UNIQUEIDENTIFIER NOT NULL,  -- Vai trò
    CONSTRAINT PK_UserRoles PRIMARY KEY (UserId, RoleId),
    CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id) ON DELETE CASCADE,
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles (Id)
);
CREATE INDEX IX_UserRoles_RoleId ON dbo.UserRoles (RoleId);

-- UserLogins: Liên kết tài khoản với nhà cung cấp đăng nhập bên ngoài (Google OAuth).
CREATE TABLE dbo.UserLogins (
    LoginProvider        VARCHAR(64)    NOT NULL,  -- Nhà cung cấp đăng nhập (vd. Google)
    ProviderKey          VARCHAR(128)   NOT NULL,  -- Mã người dùng bên nhà cung cấp (Google "sub")
    ProviderDisplayName  NVARCHAR(MAX)  NULL,  -- Tên hiển thị của nhà cung cấp
    UserId               UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản liên quan
    CONSTRAINT PK_UserLogins PRIMARY KEY (LoginProvider, ProviderKey),
    CONSTRAINT FK_UserLogins_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id) ON DELETE CASCADE
);
CREATE INDEX IX_UserLogins_UserId ON dbo.UserLogins (UserId);

-- UserTokens: Token xác nhận email, đặt lại mật khẩu, refresh token.
CREATE TABLE dbo.UserTokens (
    UserId          UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản liên quan
    LoginProvider   VARCHAR(64)    NOT NULL,  -- Nguồn tạo token
    Name            VARCHAR(64)    NOT NULL,  -- Loại token
    Value           NVARCHAR(MAX)  NULL,  -- Giá trị token
    CONSTRAINT PK_UserTokens PRIMARY KEY (UserId, LoginProvider, Name),
    CONSTRAINT FK_UserTokens_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id) ON DELETE CASCADE
);

-- Bảng của ASP.NET Core Identity (không thể hiện trên ERD; IdentityDbContext yêu cầu)
-- UserClaims: Claim của người dùng (bảng của ASP.NET Core Identity, không thể hiện trên ERD).
CREATE TABLE dbo.UserClaims (
    Id          INT IDENTITY(1,1) NOT NULL,  -- Khóa chính tự tăng
    UserId      UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản liên quan
    ClaimType   NVARCHAR(MAX)  NULL,  -- Loại claim
    ClaimValue  NVARCHAR(MAX)  NULL,  -- Giá trị claim
    CONSTRAINT PK_UserClaims PRIMARY KEY (Id),
    CONSTRAINT FK_UserClaims_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id) ON DELETE CASCADE
);
CREATE INDEX IX_UserClaims_UserId ON dbo.UserClaims (UserId);

-- RoleClaims: Claim của vai trò (bảng của ASP.NET Core Identity, không thể hiện trên ERD).
CREATE TABLE dbo.RoleClaims (
    Id          INT IDENTITY(1,1) NOT NULL,  -- Khóa chính tự tăng
    RoleId      UNIQUEIDENTIFIER NOT NULL,  -- Vai trò
    ClaimType   NVARCHAR(MAX)  NULL,  -- Loại claim
    ClaimValue  NVARCHAR(MAX)  NULL,  -- Giá trị claim
    CONSTRAINT PK_RoleClaims PRIMARY KEY (Id),
    CONSTRAINT FK_RoleClaims_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles (Id) ON DELETE CASCADE
);
CREATE INDEX IX_RoleClaims_RoleId ON dbo.RoleClaims (RoleId);

-- UserConsents: Lịch sử đồng ý / rút lại đồng ý xử lý dữ liệu cá nhân theo từng mục đích (Nghị định 13/2023/NĐ-CP, Luật Bảo vệ dữ liệu cá nhân). Chỉ thêm, không sửa.
CREATE TABLE dbo.UserConsents (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId          UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản liên quan
    Purpose         TINYINT        NOT NULL,  -- Mục đích xử lý dữ liệu. 1 TermsOfService, 2 PrivacyPolicy, 3 AIProcessing, 4 ShareProfileWithEmployers, 5 MarketingEmail
    PolicyVersion   VARCHAR(20)    NOT NULL,  -- Phiên bản chính sách đã đồng ý
    IsGranted       BIT            NOT NULL,  -- Đồng ý (1) hay từ chối (0)
    GrantedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_UserConsents_GrantedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm đồng ý (UTC)
    WithdrawnAt     DATETIME2(0)   NULL,  -- Thời điểm rút lại đồng ý
    IpAddress       VARCHAR(45)    NULL,  -- Địa chỉ IP khi đồng ý
    CONSTRAINT PK_UserConsents PRIMARY KEY (Id),
    CONSTRAINT FK_UserConsents_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_UserConsents_Purpose CHECK (Purpose BETWEEN 1 AND 5)
);
CREATE INDEX IX_UserConsents_User_Purpose ON dbo.UserConsents (UserId, Purpose, GrantedAt DESC);

-- Notifications: Thông báo trong ứng dụng gửi đến người dùng, có trạng thái đã đọc.
CREATE TABLE dbo.Notifications (
    Id                 UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId             UNIQUEIDENTIFIER NOT NULL,  -- Người nhận thông báo
    Type               VARCHAR(50)    NOT NULL,  -- Loại thông báo (vd. application.status_changed)
    Title              NVARCHAR(200)  NOT NULL,  -- Tiêu đề
    Body               NVARCHAR(1000) NOT NULL,  -- Nội dung thông báo
    LinkUrl            VARCHAR(500)   NULL,  -- Đường dẫn khi bấm vào thông báo
    RelatedEntityType  VARCHAR(30)    NULL,  -- Loại đối tượng liên quan
    RelatedEntityId    UNIQUEIDENTIFIER NULL,  -- Id đối tượng liên quan (chỉ để hiển thị, không có khóa ngoại)
    ReadAt             DATETIME2(0)   NULL,  -- Thời điểm đã đọc; NULL = chưa đọc
    CreatedAt          DATETIME2(0)   NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_Notifications PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Notifications_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id) ON DELETE CASCADE
);
CREATE CLUSTERED INDEX CX_Notifications_User_CreatedAt ON dbo.Notifications (UserId, CreatedAt);
CREATE INDEX IX_Notifications_Unread ON dbo.Notifications (UserId, ReadAt) INCLUDE (CreatedAt);

-- EmailOutbox: Hàng đợi và nhật ký email hệ thống gửi đi (mời phỏng vấn, đổi trạng thái hồ sơ), có thử lại khi lỗi.
CREATE TABLE dbo.EmailOutbox (
    Id              UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId          UNIQUEIDENTIFIER NULL,  -- Người nhận (nếu là người dùng trong hệ thống)
    ToEmail         VARCHAR(256)   NOT NULL,  -- Địa chỉ email nhận
    Subject         NVARCHAR(255)  NOT NULL,  -- Tiêu đề email
    BodyHtml        NVARCHAR(MAX)  NULL,  -- Nội dung email (xóa sau 90 ngày)
    TemplateCode    VARCHAR(50)    NOT NULL,  -- Mã mẫu email
    Status          TINYINT        NOT NULL CONSTRAINT DF_EmailOutbox_Status DEFAULT (0),  -- Trạng thái gửi. 0 Queued, 1 Sent, 2 Failed
    Attempts        TINYINT        NOT NULL CONSTRAINT DF_EmailOutbox_Attempts DEFAULT (0),  -- Số lần đã thử gửi
    LastError       NVARCHAR(1000) NULL,  -- Lỗi gần nhất
    SentAt          DATETIME2(0)   NULL,  -- Thời điểm gửi thành công
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_EmailOutbox_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_EmailOutbox PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_EmailOutbox_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_EmailOutbox_Status CHECK (Status BETWEEN 0 AND 2)
);
CREATE CLUSTERED INDEX CX_EmailOutbox_Status_CreatedAt ON dbo.EmailOutbox (Status, CreatedAt);
CREATE INDEX IX_EmailOutbox_UserId ON dbo.EmailOutbox (UserId);
GO

/* =====================================================================
   2. COMPANY & RECRUITER
   ===================================================================== */

-- Companies: Thông tin công ty tuyển dụng: tên tiếng Việt / tiếng Anh, mã số thuế, liên hệ, logo, trạng thái xác minh.
CREATE TABLE dbo.Companies (
    Id                       UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    NameVi                   NVARCHAR(255)  NOT NULL,  -- Tên công ty tiếng Việt (vd. Công ty TNHH Phần mềm ABC)
    NameEn                   NVARCHAR(255)  NULL,  -- Tên công ty tiếng Anh
    ShortName                NVARCHAR(100)  NULL,  -- Tên thương hiệu hiển thị trên tin tuyển dụng
    TaxIdentificationNumber  VARCHAR(14)    NOT NULL,  -- Mã số thuế: 10 số, hoặc 10 số + "-" + 3 số cho chi nhánh; duy nhất
    IndustryId               UNIQUEIDENTIFIER NOT NULL,  -- Lĩnh vực hoạt động
    CompanySize              TINYINT        NOT NULL,  -- Quy mô công ty
    Email                    VARCHAR(256)   NOT NULL,  -- Email liên hệ của công ty
    PhoneNumber              VARCHAR(15)    NOT NULL,  -- Số điện thoại (định dạng E.164, +84...)
    Website                  VARCHAR(255)   NULL,  -- Website công ty
    LogoUrl                  VARCHAR(500)   NULL,  -- Đường dẫn logo
    Description              NVARCHAR(4000) NULL,  -- Mô tả
    ProvinceCode             INT            NOT NULL,  -- Tỉnh / thành phố đặt trụ sở
    WardCode                 INT            NULL,  -- Phường / xã đặt trụ sở
    StreetAddress            NVARCHAR(255)  NULL,  -- Số nhà, tên đường
    VerificationStatus       TINYINT        NOT NULL CONSTRAINT DF_Companies_VerificationStatus DEFAULT (0),  -- Trạng thái xác minh hiện tại (bản sao của dòng mới nhất trong CompanyVerifications). 0 Pending, 1 Approved, 2 Rejected, 3 Suspended
    CreatedByUserId          UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản nhà tuyển dụng đã đăng ký công ty
    CreatedAt                DATETIME2(0)   NOT NULL CONSTRAINT DF_Companies_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt                DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    DeletedAt                DATETIME2(0)   NULL,  -- Thời điểm xóa mềm (UTC); NULL = chưa xóa
    CONSTRAINT PK_Companies PRIMARY KEY (Id),
    CONSTRAINT UQ_Companies_TaxIdentificationNumber UNIQUE (TaxIdentificationNumber),
    CONSTRAINT FK_Companies_Industries FOREIGN KEY (IndustryId) REFERENCES dbo.Industries (Id),
    CONSTRAINT FK_Companies_Provinces FOREIGN KEY (ProvinceCode) REFERENCES dbo.Provinces (Code),
    CONSTRAINT FK_Companies_Wards FOREIGN KEY (WardCode) REFERENCES dbo.Wards (Code),
    CONSTRAINT FK_Companies_CreatedByUser FOREIGN KEY (CreatedByUserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_Companies_CompanySize CHECK (CompanySize BETWEEN 1 AND 5),
    CONSTRAINT CK_Companies_VerificationStatus CHECK (VerificationStatus BETWEEN 0 AND 3),
    CONSTRAINT CK_Companies_TaxId CHECK (
        TaxIdentificationNumber LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
        OR TaxIdentificationNumber LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]'),
    CONSTRAINT CK_Companies_Phone CHECK (PhoneNumber LIKE '+84%' AND PhoneNumber NOT LIKE '+84%[^0-9]%')
);
CREATE INDEX IX_Companies_IndustryId ON dbo.Companies (IndustryId);
CREATE INDEX IX_Companies_ProvinceCode ON dbo.Companies (ProvinceCode);
CREATE INDEX IX_Companies_WardCode ON dbo.Companies (WardCode);
CREATE INDEX IX_Companies_CreatedByUserId ON dbo.Companies (CreatedByUserId);

-- CompanyVerifications: Lịch sử duyệt công ty của quản trị viên (gửi duyệt, duyệt, từ chối, đình chỉ, khôi phục). Chỉ thêm, không sửa.
CREATE TABLE dbo.CompanyVerifications (
    Id                UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    CompanyId         UNIQUEIDENTIFIER NOT NULL,  -- Công ty
    Decision          TINYINT        NOT NULL,  -- Quyết định. 0 Submitted, 1 Approved, 2 Rejected, 3 Suspended, 4 Reinstated
    Reason            NVARCHAR(1000) NULL,  -- Lý do (bắt buộc khi từ chối / đình chỉ)
    DocumentUrl       VARCHAR(500)   NULL,  -- Tệp giấy phép kinh doanh
    SubmittedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_CompanyVerifications_SubmittedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm gửi
    ReviewedByUserId  UNIQUEIDENTIFIER NULL,  -- Quản trị viên duyệt
    ReviewedAt        DATETIME2(0)   NULL,  -- Thời điểm duyệt
    CONSTRAINT PK_CompanyVerifications PRIMARY KEY (Id),
    CONSTRAINT FK_CompanyVerifications_Companies FOREIGN KEY (CompanyId) REFERENCES dbo.Companies (Id),
    CONSTRAINT FK_CompanyVerifications_ReviewedByUser FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_CompanyVerifications_Decision CHECK (Decision BETWEEN 0 AND 4),
    CONSTRAINT CK_CompanyVerifications_Reason CHECK (Decision NOT IN (2, 3) OR Reason IS NOT NULL)
);
CREATE INDEX IX_CompanyVerifications_CompanyId ON dbo.CompanyVerifications (CompanyId, SubmittedAt);
CREATE INDEX IX_CompanyVerifications_Queue ON dbo.CompanyVerifications (Decision, SubmittedAt) WHERE ReviewedAt IS NULL;
CREATE INDEX IX_CompanyVerifications_ReviewedByUserId ON dbo.CompanyVerifications (ReviewedByUserId);

-- EmployerProfiles: Hồ sơ của tài khoản nhà tuyển dụng (người đại diện tuyển dụng).
CREATE TABLE dbo.EmployerProfiles (
    Id            UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId        UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản đăng nhập (quan hệ 1-1)
    FullName      NVARCHAR(150)  NOT NULL,  -- Họ và tên đầy đủ
    JobTitle      NVARCHAR(100)  NULL,  -- Chức danh
    PhoneNumber   VARCHAR(15)    NULL,  -- Số điện thoại (định dạng E.164, +84...)
    AvatarUrl     VARCHAR(500)   NULL,  -- Đường dẫn ảnh đại diện
    CreatedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_EmployerProfiles_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt     DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    DeletedAt     DATETIME2(0)   NULL,  -- Thời điểm xóa mềm (UTC); NULL = chưa xóa
    CONSTRAINT PK_EmployerProfiles PRIMARY KEY (Id),
    CONSTRAINT UQ_EmployerProfiles_UserId UNIQUE (UserId),
    CONSTRAINT FK_EmployerProfiles_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_EmployerProfiles_Phone CHECK (PhoneNumber IS NULL OR (PhoneNumber LIKE '+84%' AND PhoneNumber NOT LIKE '+84%[^0-9]%'))
);

-- CompanyRecruiters: Lịch sử thành viên giữa nhà tuyển dụng và công ty. Mỗi nhà tuyển dụng thuộc một công ty tại một thời điểm, có thể chuyển công ty sau.
CREATE TABLE dbo.CompanyRecruiters (
    Id                           UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    CompanyId                    UNIQUEIDENTIFIER NOT NULL,  -- Công ty
    EmployerProfileId            UNIQUEIDENTIFIER NOT NULL,  -- Nhà tuyển dụng
    IsOwner                      BIT            NOT NULL CONSTRAINT DF_CompanyRecruiters_IsOwner DEFAULT (0),  -- Là chủ sở hữu (người duyệt thành viên mới)
    JoinStatus                   TINYINT        NOT NULL CONSTRAINT DF_CompanyRecruiters_JoinStatus DEFAULT (0),  -- Trạng thái thành viên. 0 Requested, 1 Active, 2 Rejected, 3 Left, 4 Removed
    RequestedAt                  DATETIME2(0)   NOT NULL CONSTRAINT DF_CompanyRecruiters_RequestedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm xin gia nhập
    ApprovedByEmployerProfileId  UNIQUEIDENTIFIER NULL,  -- Chủ công ty đã duyệt yêu cầu
    StartedAt                    DATETIME2(0)   NULL,  -- Ngày bắt đầu làm việc cho công ty
    EndedAt                      DATETIME2(0)   NULL,  -- Ngày rời công ty; NULL = đang làm
    CONSTRAINT PK_CompanyRecruiters PRIMARY KEY (Id),
    CONSTRAINT FK_CompanyRecruiters_Companies FOREIGN KEY (CompanyId) REFERENCES dbo.Companies (Id),
    CONSTRAINT FK_CompanyRecruiters_EmployerProfiles FOREIGN KEY (EmployerProfileId) REFERENCES dbo.EmployerProfiles (Id),
    CONSTRAINT FK_CompanyRecruiters_ApprovedBy FOREIGN KEY (ApprovedByEmployerProfileId) REFERENCES dbo.EmployerProfiles (Id),
    CONSTRAINT CK_CompanyRecruiters_JoinStatus CHECK (JoinStatus BETWEEN 0 AND 4),
    CONSTRAINT CK_CompanyRecruiters_Dates CHECK (EndedAt IS NULL OR StartedAt IS NULL OR EndedAt >= StartedAt)
);
-- mỗi nhà tuyển dụng chỉ thuộc một công ty tại một thời điểm
CREATE UNIQUE INDEX UQ_CompanyRecruiters_OneCurrentCompany ON dbo.CompanyRecruiters (EmployerProfileId) WHERE JoinStatus IN (0, 1);
-- mỗi công ty chỉ có một chủ sở hữu đang hoạt động
CREATE UNIQUE INDEX UQ_CompanyRecruiters_OneOwner ON dbo.CompanyRecruiters (CompanyId) WHERE IsOwner = 1 AND JoinStatus = 1;
CREATE INDEX IX_CompanyRecruiters_CompanyId ON dbo.CompanyRecruiters (CompanyId, JoinStatus);
CREATE INDEX IX_CompanyRecruiters_ApprovedBy ON dbo.CompanyRecruiters (ApprovedByEmployerProfileId);
GO

/* =====================================================================
   3. JOBS
   ===================================================================== */

-- JobPostings: Tin tuyển dụng / thực tập: loại công việc, hình thức làm việc, mức lương (VND), địa điểm, hạn nộp, trạng thái kiểm duyệt.
CREATE TABLE dbo.JobPostings (
    Id                          UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    CompanyId                   UNIQUEIDENTIFIER NOT NULL,  -- Công ty sở hữu tin (tin vẫn thuộc công ty khi nhà tuyển dụng nghỉ)
    CreatedByEmployerProfileId  UNIQUEIDENTIFIER NOT NULL,  -- Nhà tuyển dụng tạo tin
    IndustryId                  UNIQUEIDENTIFIER NOT NULL,  -- Lĩnh vực (dùng cho bộ lọc)
    JobType                     TINYINT        NOT NULL,  -- Loại công việc. 1 Internship, 2 Full-time, 3 Part-time
    WorkMode                    TINYINT        NOT NULL,  -- Hình thức làm việc. 1 On-site, 2 Remote, 3 Hybrid
    ExperienceLevel             TINYINT        NOT NULL,  -- Cấp độ kinh nghiệm. 1 Student, 2 Fresh graduate, 3 Junior, 4 Middle+
    SalaryMin                   DECIMAL(18,2)  NULL,  -- Lương tối thiểu (VND); NULL khi thỏa thuận
    SalaryMax                   DECIMAL(18,2)  NULL,  -- Lương tối đa (VND)
    SalaryPeriod                TINYINT        NULL,  -- Kỳ trả lương. 1 Month, 2 Hour, 3 Project
    IsSalaryNegotiable          BIT            NOT NULL CONSTRAINT DF_JobPostings_IsSalaryNegotiable DEFAULT (0),  -- Lương thỏa thuận
    Headcount                   SMALLINT       NOT NULL CONSTRAINT DF_JobPostings_Headcount DEFAULT (1),  -- Số lượng cần tuyển (chỉ để hiển thị)
    DurationMonths              TINYINT        NULL,  -- Thời gian thực tập / thử việc (tháng)
    ProvinceCode                INT            NOT NULL,  -- Tỉnh / thành phố làm việc
    WardCode                    INT            NULL,  -- Phường / xã làm việc
    StreetAddress               NVARCHAR(255)  NULL,  -- Số nhà, tên đường
    ApplicationDeadline         DATE           NOT NULL,  -- Hạn nộp hồ sơ (ngày cuối, giờ Việt Nam)
    Status                      TINYINT        NOT NULL CONSTRAINT DF_JobPostings_Status DEFAULT (0),  -- Trạng thái tin. 0 Draft, 1 PendingReview, 2 Published, 3 Rejected, 4 Closed, 5 Expired
    PublishedAt                 DATETIME2(0)   NULL,  -- Thời điểm đăng tin
    ClosedAt                    DATETIME2(0)   NULL,  -- Thời điểm đóng tin
    ClosedReason                TINYINT        NULL,  -- Lý do đóng tin. 1 Manual, 2 DeadlinePassed, 3 CompanySuspended
    ViewCount                   INT            NOT NULL CONSTRAINT DF_JobPostings_ViewCount DEFAULT (0),  -- Số lượt xem (đầu phễu tuyển dụng)
    RowVersion                  ROWVERSION     NOT NULL,  -- Phiên bản dòng, chống ghi đè đồng thời (EF Core)
    CreatedAt                   DATETIME2(0)   NOT NULL CONSTRAINT DF_JobPostings_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt                   DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    DeletedAt                   DATETIME2(0)   NULL,  -- Thời điểm xóa mềm (UTC); NULL = chưa xóa
    CONSTRAINT PK_JobPostings PRIMARY KEY (Id),
    CONSTRAINT FK_JobPostings_Companies FOREIGN KEY (CompanyId) REFERENCES dbo.Companies (Id),
    CONSTRAINT FK_JobPostings_EmployerProfiles FOREIGN KEY (CreatedByEmployerProfileId) REFERENCES dbo.EmployerProfiles (Id),
    CONSTRAINT FK_JobPostings_Industries FOREIGN KEY (IndustryId) REFERENCES dbo.Industries (Id),
    CONSTRAINT FK_JobPostings_Provinces FOREIGN KEY (ProvinceCode) REFERENCES dbo.Provinces (Code),
    CONSTRAINT FK_JobPostings_Wards FOREIGN KEY (WardCode) REFERENCES dbo.Wards (Code),
    CONSTRAINT CK_JobPostings_JobType CHECK (JobType BETWEEN 1 AND 3),
    CONSTRAINT CK_JobPostings_WorkMode CHECK (WorkMode BETWEEN 1 AND 3),
    CONSTRAINT CK_JobPostings_ExperienceLevel CHECK (ExperienceLevel BETWEEN 1 AND 4),
    CONSTRAINT CK_JobPostings_SalaryPeriod CHECK (SalaryPeriod IS NULL OR SalaryPeriod BETWEEN 1 AND 3),
    CONSTRAINT CK_JobPostings_Status CHECK (Status BETWEEN 0 AND 5),
    CONSTRAINT CK_JobPostings_ClosedReason CHECK (ClosedReason IS NULL OR ClosedReason BETWEEN 1 AND 3),
    CONSTRAINT CK_JobPostings_ClosedNeedsReason CHECK (Status NOT IN (4, 5) OR ClosedReason IS NOT NULL),
    CONSTRAINT CK_JobPostings_SalaryMin CHECK (SalaryMin IS NULL OR SalaryMin >= 0),
    CONSTRAINT CK_JobPostings_SalaryRange CHECK (SalaryMax IS NULL OR SalaryMin IS NULL OR SalaryMax >= SalaryMin),
    CONSTRAINT CK_JobPostings_SalaryOrNegotiable CHECK (IsSalaryNegotiable = 1 OR SalaryMin IS NOT NULL),
    CONSTRAINT CK_JobPostings_Headcount CHECK (Headcount >= 1)
);
CREATE INDEX IX_JobPostings_Search ON dbo.JobPostings (Status, ApplicationDeadline)
    INCLUDE (CompanyId, JobType, WorkMode, ProvinceCode, IndustryId) WHERE DeletedAt IS NULL;
CREATE INDEX IX_JobPostings_Company_Status ON dbo.JobPostings (CompanyId, Status);
CREATE INDEX IX_JobPostings_CreatedBy ON dbo.JobPostings (CreatedByEmployerProfileId);
CREATE INDEX IX_JobPostings_IndustryId ON dbo.JobPostings (IndustryId);
CREATE INDEX IX_JobPostings_ProvinceCode ON dbo.JobPostings (ProvinceCode);
CREATE INDEX IX_JobPostings_WardCode ON dbo.JobPostings (WardCode);

-- JobPostingTranslations: Nội dung tin tuyển dụng theo ngôn ngữ (bắt buộc tiếng Việt, tùy chọn tiếng Anh).
CREATE TABLE dbo.JobPostingTranslations (
    JobPostingId   UNIQUEIDENTIFIER NOT NULL,  -- Tin tuyển dụng
    LanguageCode   CHAR(2)        NOT NULL,  -- Mã ngôn ngữ (vi / en)
    Title          NVARCHAR(200)  NOT NULL,  -- Tiêu đề tin
    Description    NVARCHAR(MAX)  NOT NULL,  -- Mô tả công việc
    Requirements   NVARCHAR(MAX)  NOT NULL,  -- Yêu cầu ứng viên
    Benefits       NVARCHAR(MAX)  NULL,  -- Quyền lợi
    CONSTRAINT PK_JobPostingTranslations PRIMARY KEY (JobPostingId, LanguageCode),
    CONSTRAINT FK_JobPostingTranslations_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id) ON DELETE CASCADE,
    CONSTRAINT CK_JobPostingTranslations_Language CHECK (LanguageCode IN ('vi', 'en'))
);

-- JobPostingSkills: Kỹ năng yêu cầu / ưu tiên của tin tuyển dụng (bảng trung gian).
CREATE TABLE dbo.JobPostingSkills (
    JobPostingId         UNIQUEIDENTIFIER NOT NULL,  -- Tin tuyển dụng
    SkillId              UNIQUEIDENTIFIER NOT NULL,  -- Kỹ năng
    IsRequired           BIT            NOT NULL CONSTRAINT DF_JobPostingSkills_IsRequired DEFAULT (1),  -- Bắt buộc (1) hay ưu tiên (0)
    MinProficiencyLevel  TINYINT        NULL,  -- Mức thành thạo tối thiểu (1-5)
    CONSTRAINT PK_JobPostingSkills PRIMARY KEY (JobPostingId, SkillId),
    CONSTRAINT FK_JobPostingSkills_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id) ON DELETE CASCADE,
    CONSTRAINT FK_JobPostingSkills_Skills FOREIGN KEY (SkillId) REFERENCES dbo.Skills (Id),
    CONSTRAINT CK_JobPostingSkills_Level CHECK (MinProficiencyLevel IS NULL OR MinProficiencyLevel BETWEEN 1 AND 5)
);
CREATE INDEX IX_JobPostingSkills_SkillId ON dbo.JobPostingSkills (SkillId);

-- JobPostingReviews: Lịch sử kiểm duyệt tin tuyển dụng của quản trị viên. Chỉ thêm, không sửa.
CREATE TABLE dbo.JobPostingReviews (
    Id                UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    JobPostingId      UNIQUEIDENTIFIER NOT NULL,  -- Tin tuyển dụng
    Decision          TINYINT        NOT NULL,  -- Quyết định. 0 Submitted, 1 Approved, 2 Rejected
    Reason            NVARCHAR(1000) NULL,  -- Lý do (bắt buộc khi từ chối / đình chỉ)
    SubmittedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_JobPostingReviews_SubmittedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm gửi
    ReviewedByUserId  UNIQUEIDENTIFIER NULL,  -- Quản trị viên duyệt
    ReviewedAt        DATETIME2(0)   NULL,  -- Thời điểm duyệt
    CONSTRAINT PK_JobPostingReviews PRIMARY KEY (Id),
    CONSTRAINT FK_JobPostingReviews_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id),
    CONSTRAINT FK_JobPostingReviews_ReviewedByUser FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.Users (Id),
    CONSTRAINT CK_JobPostingReviews_Decision CHECK (Decision BETWEEN 0 AND 2),
    CONSTRAINT CK_JobPostingReviews_Reason CHECK (Decision <> 2 OR Reason IS NOT NULL)
);
CREATE INDEX IX_JobPostingReviews_JobPostingId ON dbo.JobPostingReviews (JobPostingId, SubmittedAt);
CREATE INDEX IX_JobPostingReviews_Queue ON dbo.JobPostingReviews (Decision, SubmittedAt) WHERE ReviewedAt IS NULL;
CREATE INDEX IX_JobPostingReviews_ReviewedByUserId ON dbo.JobPostingReviews (ReviewedByUserId);

-- ExportLogs tham chiếu Companies và JobPostings nên được tạo sau hai bảng này
-- ExportLogs: Nhật ký xuất danh sách ứng viên / thống kê ra Excel, PDF (kiểm toán dữ liệu cá nhân). Chỉ thêm, không sửa.
CREATE TABLE dbo.ExportLogs (
    Id            UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId        UNIQUEIDENTIFIER NOT NULL,  -- Người thực hiện xuất dữ liệu
    CompanyId     UNIQUEIDENTIFIER NULL,  -- Công ty của dữ liệu xuất
    JobPostingId  UNIQUEIDENTIFIER NULL,  -- Tin tuyển dụng của danh sách xuất
    ExportType    TINYINT        NOT NULL,  -- Loại dữ liệu xuất. 1 ApplicantList, 2 Statistics
    Format        TINYINT        NOT NULL,  -- Định dạng tệp. 1 Excel, 2 PDF
    [RowCount]    INT            NOT NULL,  -- Số dòng đã xuất
    FilterJson    NVARCHAR(1000) NULL,  -- Bộ lọc đã dùng (JSON)
    ExportedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_ExportLogs_ExportedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm xuất (UTC)
    CONSTRAINT PK_ExportLogs PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_ExportLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT FK_ExportLogs_Companies FOREIGN KEY (CompanyId) REFERENCES dbo.Companies (Id),
    CONSTRAINT FK_ExportLogs_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id),
    CONSTRAINT CK_ExportLogs_ExportType CHECK (ExportType BETWEEN 1 AND 2),
    CONSTRAINT CK_ExportLogs_Format CHECK (Format BETWEEN 1 AND 2)
);
CREATE CLUSTERED INDEX CX_ExportLogs_User_ExportedAt ON dbo.ExportLogs (UserId, ExportedAt);
CREATE INDEX IX_ExportLogs_CompanyId ON dbo.ExportLogs (CompanyId);
CREATE INDEX IX_ExportLogs_JobPostingId ON dbo.ExportLogs (JobPostingId);
GO

/* =====================================================================
   5. STUDENT & CV
   ===================================================================== */

-- StudentProfiles: Hồ sơ cá nhân của sinh viên, địa chỉ và cài đặt quyền riêng tư.
CREATE TABLE dbo.StudentProfiles (
    Id                    UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    UserId                UNIQUEIDENTIFIER NOT NULL,  -- Tài khoản đăng nhập (quan hệ 1-1)
    FullName              NVARCHAR(150)  NOT NULL,  -- Họ và tên đầy đủ (vd. Nguyễn Văn An)
    FamilyName            NVARCHAR(50)   NULL,  -- Họ (vd. Nguyễn)
    GivenName             NVARCHAR(50)   NULL,  -- Tên (vd. An), dùng để sắp xếp
    DateOfBirth           DATE           NULL,  -- Ngày sinh
    Gender                TINYINT        NULL,  -- Giới tính (không dùng khi so khớp). 1 Male, 2 Female, 3 Other; never used for matching
    PhoneNumber           VARCHAR(15)    NULL,  -- Số điện thoại (định dạng E.164, +84...)
    ProvinceCode          INT            NULL,  -- Tỉnh / thành phố đang sống
    WardCode              INT            NULL,  -- Phường / xã đang sống
    StreetAddress         NVARCHAR(255)  NULL,  -- Số nhà, tên đường
    Headline              NVARCHAR(200)  NULL,  -- Dòng giới thiệu ngắn (vd. Sinh viên năm 4 CNTT)
    Summary               NVARCHAR(2000) NULL,  -- Giới thiệu bản thân
    AvatarUrl             VARCHAR(500)   NULL,  -- Đường dẫn ảnh đại diện
    IsOpenToWork          BIT            NOT NULL CONSTRAINT DF_StudentProfiles_IsOpenToWork DEFAULT (1),  -- Đang tìm việc
    ShowPhoneToEmployers  BIT            NOT NULL CONSTRAINT DF_StudentProfiles_ShowPhone DEFAULT (0),  -- Cho nhà tuyển dụng xem số điện thoại (quyền riêng tư)
    ShowEmailToEmployers  BIT            NOT NULL CONSTRAINT DF_StudentProfiles_ShowEmail DEFAULT (0),  -- Cho nhà tuyển dụng xem email (quyền riêng tư)
    AllowAIProcessing     BIT            NOT NULL CONSTRAINT DF_StudentProfiles_AllowAI DEFAULT (1),  -- Cho phép AI phân tích CV và so khớp
    CreatedAt             DATETIME2(0)   NOT NULL CONSTRAINT DF_StudentProfiles_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt             DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    DeletedAt             DATETIME2(0)   NULL,  -- Thời điểm ẩn danh hóa hồ sơ; NULL = đang dùng
    CONSTRAINT PK_StudentProfiles PRIMARY KEY (Id),
    CONSTRAINT UQ_StudentProfiles_UserId UNIQUE (UserId),
    CONSTRAINT FK_StudentProfiles_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT FK_StudentProfiles_Provinces FOREIGN KEY (ProvinceCode) REFERENCES dbo.Provinces (Code),
    CONSTRAINT FK_StudentProfiles_Wards FOREIGN KEY (WardCode) REFERENCES dbo.Wards (Code),
    CONSTRAINT CK_StudentProfiles_Gender CHECK (Gender IS NULL OR Gender BETWEEN 1 AND 3),
    CONSTRAINT CK_StudentProfiles_Phone CHECK (PhoneNumber IS NULL OR (PhoneNumber LIKE '+84%' AND PhoneNumber NOT LIKE '+84%[^0-9]%'))
);
CREATE INDEX IX_StudentProfiles_ProvinceCode ON dbo.StudentProfiles (ProvinceCode);
CREATE INDEX IX_StudentProfiles_WardCode ON dbo.StudentProfiles (WardCode);

-- StudentEducations: Quá trình học tập của sinh viên: trường, ngành, năm học, GPA.
CREATE TABLE dbo.StudentEducations (
    Id                      UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    StudentProfileId        UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    UniversityId            UNIQUEIDENTIFIER NOT NULL,  -- Trường
    MajorId                 UNIQUEIDENTIFIER NULL,  -- Ngành học
    Degree                  TINYINT        NOT NULL,  -- Bậc học. 1 College, 2 Bachelor, 3 Master, 4 Other
    StartYear               SMALLINT       NOT NULL,  -- Năm bắt đầu
    ExpectedGraduationYear  SMALLINT       NULL,  -- Năm tốt nghiệp (dự kiến)
    GPA                     DECIMAL(4,2)   NULL,  -- Điểm trung bình
    GPAScale                DECIMAL(4,2)   NULL,  -- Thang điểm (4 hoặc 10)
    Description             NVARCHAR(1000) NULL,  -- Mô tả
    CreatedAt               DATETIME2(0)   NOT NULL CONSTRAINT DF_StudentEducations_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt               DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    CONSTRAINT PK_StudentEducations PRIMARY KEY (Id),
    CONSTRAINT FK_StudentEducations_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id) ON DELETE CASCADE,
    CONSTRAINT FK_StudentEducations_Universities FOREIGN KEY (UniversityId) REFERENCES dbo.Universities (Id),
    CONSTRAINT FK_StudentEducations_Majors FOREIGN KEY (MajorId) REFERENCES dbo.Majors (Id),
    CONSTRAINT CK_StudentEducations_Degree CHECK (Degree BETWEEN 1 AND 4),
    CONSTRAINT CK_StudentEducations_GPAScale CHECK (GPAScale IS NULL OR GPAScale IN (4, 10)),
    CONSTRAINT CK_StudentEducations_GPA CHECK (GPA IS NULL OR (GPA >= 0 AND GPAScale IS NOT NULL AND GPA <= GPAScale)),
    CONSTRAINT CK_StudentEducations_Years CHECK (ExpectedGraduationYear IS NULL OR ExpectedGraduationYear >= StartYear)
);
CREATE INDEX IX_StudentEducations_StudentProfileId ON dbo.StudentEducations (StudentProfileId);
CREATE INDEX IX_StudentEducations_UniversityId ON dbo.StudentEducations (UniversityId);
CREATE INDEX IX_StudentEducations_MajorId ON dbo.StudentEducations (MajorId);

-- StudentExperiences: Kinh nghiệm của sinh viên: việc làm, thực tập, dự án, hoạt động.
CREATE TABLE dbo.StudentExperiences (
    Id                UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    StudentProfileId  UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    ExperienceType    TINYINT        NOT NULL,  -- Loại kinh nghiệm. 1 Job, 2 Internship, 3 Project, 4 Activity
    Title             NVARCHAR(200)  NOT NULL,  -- Vị trí / tên dự án
    Organization      NVARCHAR(200)  NULL,  -- Tổ chức / công ty
    StartDate         DATE           NOT NULL,  -- Ngày bắt đầu
    EndDate           DATE           NULL,  -- Ngày kết thúc; NULL = đang làm
    Description       NVARCHAR(2000) NULL,  -- Mô tả
    CreatedAt         DATETIME2(0)   NOT NULL CONSTRAINT DF_StudentExperiences_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt         DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    CONSTRAINT PK_StudentExperiences PRIMARY KEY (Id),
    CONSTRAINT FK_StudentExperiences_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id) ON DELETE CASCADE,
    CONSTRAINT CK_StudentExperiences_Type CHECK (ExperienceType BETWEEN 1 AND 4),
    CONSTRAINT CK_StudentExperiences_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
CREATE INDEX IX_StudentExperiences_StudentProfileId ON dbo.StudentExperiences (StudentProfileId);

-- StudentSkills: Kỹ năng sinh viên tự khai báo, kèm mức độ thành thạo (bảng trung gian).
CREATE TABLE dbo.StudentSkills (
    StudentProfileId   UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    SkillId            UNIQUEIDENTIFIER NOT NULL,  -- Kỹ năng
    ProficiencyLevel   TINYINT        NOT NULL,  -- Mức thành thạo (1-5)
    YearsOfExperience  DECIMAL(3,1)   NULL,  -- Số năm kinh nghiệm
    CONSTRAINT PK_StudentSkills PRIMARY KEY (StudentProfileId, SkillId),
    CONSTRAINT FK_StudentSkills_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id) ON DELETE CASCADE,
    CONSTRAINT FK_StudentSkills_Skills FOREIGN KEY (SkillId) REFERENCES dbo.Skills (Id),
    CONSTRAINT CK_StudentSkills_Level CHECK (ProficiencyLevel BETWEEN 1 AND 5),
    CONSTRAINT CK_StudentSkills_Years CHECK (YearsOfExperience IS NULL OR YearsOfExperience >= 0)
);
CREATE INDEX IX_StudentSkills_SkillId ON dbo.StudentSkills (SkillId);

-- CVs: Các phiên bản CV sinh viên tải lên. Chỉ lưu thông tin tệp; tệp thật nằm trong kho lưu trữ. Không ghi đè, mỗi lần tải lên là một phiên bản mới.
CREATE TABLE dbo.CVs (
    Id                  UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    StudentProfileId    UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    Title               NVARCHAR(150)  NOT NULL,  -- Tên phiên bản CV
    LanguageCode        CHAR(2)        NOT NULL,  -- Ngôn ngữ của CV (vi / en)
    FileName            NVARCHAR(255)  NOT NULL,  -- Tên tệp gốc
    StoragePath         VARCHAR(500)   NOT NULL,  -- Đường dẫn tệp trong kho lưu trữ
    ContentType         VARCHAR(100)   NOT NULL,  -- Kiểu tệp (PDF hoặc DOCX)
    FileSizeBytes       INT            NOT NULL,  -- Dung lượng tệp (tối đa 5 MB)
    FileHashSha256      CHAR(64)       NOT NULL,  -- Mã băm SHA-256 của tệp (phát hiện trùng)
    IsDefault           BIT            NOT NULL CONSTRAINT DF_CVs_IsDefault DEFAULT (0),  -- CV mặc định của sinh viên
    ParseStatus         TINYINT        NOT NULL CONSTRAINT DF_CVs_ParseStatus DEFAULT (0),  -- Trạng thái AI phân tích CV. 0 Pending, 1 Parsed, 2 Failed, 3 Skipped
    ParsedAt            DATETIME2(0)   NULL,  -- Thời điểm phân tích
    ParserModelVersion  VARCHAR(50)    NULL,  -- Phiên bản mô hình phân tích
    ParsedText          NVARCHAR(MAX)  NULL,  -- Văn bản trích xuất từ CV
    CreatedAt           DATETIME2(0)   NOT NULL CONSTRAINT DF_CVs_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    DeletedAt           DATETIME2(0)   NULL,  -- Thời điểm xóa mềm (UTC); NULL = chưa xóa
    CONSTRAINT PK_CVs PRIMARY KEY (Id),
    CONSTRAINT FK_CVs_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id),
    CONSTRAINT CK_CVs_Language CHECK (LanguageCode IN ('vi', 'en')),
    CONSTRAINT CK_CVs_ContentType CHECK (ContentType IN ('application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
    CONSTRAINT CK_CVs_FileSize CHECK (FileSizeBytes > 0 AND FileSizeBytes <= 5242880),
    CONSTRAINT CK_CVs_ParseStatus CHECK (ParseStatus BETWEEN 0 AND 3)
);
CREATE INDEX IX_CVs_StudentProfileId ON dbo.CVs (StudentProfileId);
CREATE UNIQUE INDEX UQ_CVs_OneDefault ON dbo.CVs (StudentProfileId) WHERE IsDefault = 1 AND DeletedAt IS NULL;

-- CVParsedSkills: Kỹ năng do AI trích xuất từ một phiên bản CV, kèm độ tin cậy.
CREATE TABLE dbo.CVParsedSkills (
    CVId          UNIQUEIDENTIFIER NOT NULL,  -- Phiên bản CV
    SkillId       UNIQUEIDENTIFIER NOT NULL,  -- Kỹ năng
    Confidence    DECIMAL(5,4)   NOT NULL,  -- Độ tin cậy của AI (0-1)
    EvidenceText  NVARCHAR(500)  NULL,  -- Đoạn văn bản trong CV làm căn cứ
    CONSTRAINT PK_CVParsedSkills PRIMARY KEY (CVId, SkillId),
    CONSTRAINT FK_CVParsedSkills_CVs FOREIGN KEY (CVId) REFERENCES dbo.CVs (Id) ON DELETE CASCADE,
    CONSTRAINT FK_CVParsedSkills_Skills FOREIGN KEY (SkillId) REFERENCES dbo.Skills (Id),
    CONSTRAINT CK_CVParsedSkills_Confidence CHECK (Confidence BETWEEN 0 AND 1)
);
CREATE INDEX IX_CVParsedSkills_SkillId ON dbo.CVParsedSkills (SkillId);
GO

/* =====================================================================
   4. APPLICATIONS & INTERVIEWS
   ===================================================================== */

-- Applications: Hồ sơ ứng tuyển của sinh viên vào một tin tuyển dụng, lưu đúng phiên bản CV và thư giới thiệu đã nộp. Mỗi sinh viên chỉ ứng tuyển một lần cho mỗi tin.
CREATE TABLE dbo.Applications (
    Id                   UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    StudentProfileId     UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    JobPostingId         UNIQUEIDENTIFIER NOT NULL,  -- Tin tuyển dụng
    CVId                 UNIQUEIDENTIFIER NOT NULL,  -- Đúng phiên bản CV đã nộp
    CoverLetter          NVARCHAR(4000) NULL,  -- Thư giới thiệu (lưu lại tại thời điểm nộp, không sửa được)
    CurrentStatusId      TINYINT        NOT NULL CONSTRAINT DF_Applications_CurrentStatusId DEFAULT (1),  -- Trạng thái hiện tại (bản sao của dòng mới nhất trong lịch sử)
    SubmittedAt          DATETIME2(0)   NOT NULL CONSTRAINT DF_Applications_SubmittedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm nộp hồ sơ
    LastStatusChangedAt  DATETIME2(0)   NOT NULL CONSTRAINT DF_Applications_LastStatusChangedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm đổi trạng thái gần nhất
    RowVersion           ROWVERSION     NOT NULL,  -- Phiên bản dòng, chống ghi đè đồng thời (EF Core)
    CONSTRAINT PK_Applications PRIMARY KEY (Id),
    CONSTRAINT UQ_Applications_Student_Posting UNIQUE (StudentProfileId, JobPostingId),   -- không cho ứng tuyển lại
    CONSTRAINT FK_Applications_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id),
    CONSTRAINT FK_Applications_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id),
    CONSTRAINT FK_Applications_CVs FOREIGN KEY (CVId) REFERENCES dbo.CVs (Id),
    CONSTRAINT FK_Applications_ApplicationStatuses FOREIGN KEY (CurrentStatusId) REFERENCES dbo.ApplicationStatuses (Id)
);
CREATE INDEX IX_Applications_Posting_Status ON dbo.Applications (JobPostingId, CurrentStatusId);
CREATE INDEX IX_Applications_Student_SubmittedAt ON dbo.Applications (StudentProfileId, SubmittedAt DESC);
CREATE INDEX IX_Applications_CVId ON dbo.Applications (CVId);

-- ApplicationStatusHistory: Lịch sử thay đổi trạng thái hồ sơ ứng tuyển (từ, đến, ai đổi, khi nào, lý do).
CREATE TABLE dbo.ApplicationStatusHistory (
    Id               UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    ApplicationId    UNIQUEIDENTIFIER NOT NULL,  -- Hồ sơ ứng tuyển
    FromStatusId     TINYINT        NULL,  -- Trạng thái trước
    ToStatusId       TINYINT        NOT NULL,  -- Trạng thái mới
    ChangedByUserId  UNIQUEIDENTIFIER NOT NULL,  -- Người đổi trạng thái
    ChangedAt        DATETIME2(0)   NOT NULL CONSTRAINT DF_ApplicationStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm đổi (UTC)
    Note             NVARCHAR(1000) NULL,  -- Ghi chú
    CONSTRAINT PK_ApplicationStatusHistory PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_ApplicationStatusHistory_Applications FOREIGN KEY (ApplicationId) REFERENCES dbo.Applications (Id),
    CONSTRAINT FK_ApplicationStatusHistory_FromStatus FOREIGN KEY (FromStatusId) REFERENCES dbo.ApplicationStatuses (Id),
    CONSTRAINT FK_ApplicationStatusHistory_ToStatus FOREIGN KEY (ToStatusId) REFERENCES dbo.ApplicationStatuses (Id),
    CONSTRAINT FK_ApplicationStatusHistory_ChangedByUser FOREIGN KEY (ChangedByUserId) REFERENCES dbo.Users (Id)
);
CREATE CLUSTERED INDEX CX_ApplicationStatusHistory_App_ChangedAt ON dbo.ApplicationStatusHistory (ApplicationId, ChangedAt);
CREATE INDEX IX_ApplicationStatusHistory_ToStatus ON dbo.ApplicationStatusHistory (ToStatusId, ChangedAt);
CREATE INDEX IX_ApplicationStatusHistory_ChangedBy ON dbo.ApplicationStatusHistory (ChangedByUserId);

-- Interviews: Một vòng phỏng vấn của hồ sơ ứng tuyển: hình thức, địa điểm / link họp, trạng thái, kết quả.
CREATE TABLE dbo.Interviews (
    Id                          UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    ApplicationId               UNIQUEIDENTIFIER NOT NULL,  -- Hồ sơ ứng tuyển
    RoundNumber                 TINYINT        NOT NULL,  -- Vòng phỏng vấn thứ mấy
    Title                       NVARCHAR(150)  NOT NULL,  -- Tên vòng (vd. Phỏng vấn kỹ thuật)
    Mode                        TINYINT        NOT NULL,  -- Hình thức phỏng vấn. 1 Online, 2 Onsite, 3 Phone
    MeetingUrl                  VARCHAR(500)   NULL,  -- Link họp trực tuyến
    Location                    NVARCHAR(255)  NULL,  -- Địa điểm phỏng vấn trực tiếp
    DurationMinutes             SMALLINT       NOT NULL,  -- Thời lượng (phút)
    SelectedSlotId              UNIQUEIDENTIFIER NULL,  -- Khung giờ sinh viên đã chọn
    Status                      TINYINT        NOT NULL CONSTRAINT DF_Interviews_Status DEFAULT (0),  -- Trạng thái phỏng vấn. 0 SlotsOffered, 1 Scheduled, 2 Completed, 3 Cancelled, 4 NoShow
    Outcome                     TINYINT        NULL,  -- Kết quả phỏng vấn. 1 Pass, 2 Fail, 3 Pending
    Feedback                    NVARCHAR(2000) NULL,  -- Nhận xét của nhà tuyển dụng
    CreatedByEmployerProfileId  UNIQUEIDENTIFIER NOT NULL,  -- Nhà tuyển dụng tạo lịch phỏng vấn
    CreatedAt                   DATETIME2(0)   NOT NULL CONSTRAINT DF_Interviews_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    UpdatedAt                   DATETIME2(0)   NULL,  -- Thời điểm cập nhật gần nhất (UTC)
    CONSTRAINT PK_Interviews PRIMARY KEY (Id),
    CONSTRAINT UQ_Interviews_Application_Round UNIQUE (ApplicationId, RoundNumber),
    CONSTRAINT FK_Interviews_Applications FOREIGN KEY (ApplicationId) REFERENCES dbo.Applications (Id),
    CONSTRAINT FK_Interviews_EmployerProfiles FOREIGN KEY (CreatedByEmployerProfileId) REFERENCES dbo.EmployerProfiles (Id),
    CONSTRAINT CK_Interviews_Mode CHECK (Mode BETWEEN 1 AND 3),
    CONSTRAINT CK_Interviews_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT CK_Interviews_Outcome CHECK (Outcome IS NULL OR Outcome BETWEEN 1 AND 3),
    CONSTRAINT CK_Interviews_Duration CHECK (DurationMinutes > 0),
    CONSTRAINT CK_Interviews_OnlineUrl CHECK (Mode <> 1 OR MeetingUrl IS NOT NULL),
    CONSTRAINT CK_Interviews_OnsiteLocation CHECK (Mode <> 2 OR Location IS NOT NULL)
);
CREATE INDEX IX_Interviews_CreatedBy ON dbo.Interviews (CreatedByEmployerProfileId);

-- InterviewSlots: Các khung giờ phỏng vấn nhà tuyển dụng đề xuất; sinh viên chọn một khung giờ.
CREATE TABLE dbo.InterviewSlots (
    Id           UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    InterviewId  UNIQUEIDENTIFIER NOT NULL,  -- Vòng phỏng vấn
    StartAt      DATETIME2(0)   NOT NULL,  -- Giờ bắt đầu (UTC)
    EndAt        DATETIME2(0)   NOT NULL,  -- Giờ kết thúc (UTC)
    IsBooked     BIT            NOT NULL CONSTRAINT DF_InterviewSlots_IsBooked DEFAULT (0),  -- Đã được chọn
    CONSTRAINT PK_InterviewSlots PRIMARY KEY (Id),
    CONSTRAINT UQ_InterviewSlots_Interview_Start UNIQUE (InterviewId, StartAt),
    CONSTRAINT FK_InterviewSlots_Interviews FOREIGN KEY (InterviewId) REFERENCES dbo.Interviews (Id) ON DELETE CASCADE,
    CONSTRAINT CK_InterviewSlots_Times CHECK (EndAt > StartAt)
);

ALTER TABLE dbo.Interviews ADD CONSTRAINT FK_Interviews_SelectedSlot
    FOREIGN KEY (SelectedSlotId) REFERENCES dbo.InterviewSlots (Id);
CREATE UNIQUE INDEX UQ_Interviews_SelectedSlotId ON dbo.Interviews (SelectedSlotId) WHERE SelectedSlotId IS NOT NULL;

-- Messages: Tin nhắn giữa sinh viên và nhà tuyển dụng trong phạm vi một hồ sơ ứng tuyển.
CREATE TABLE dbo.Messages (
    Id             UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    ApplicationId  UNIQUEIDENTIFIER NOT NULL,  -- Hồ sơ ứng tuyển
    SenderUserId   UNIQUEIDENTIFIER NOT NULL,  -- Người gửi
    Body           NVARCHAR(4000) NOT NULL,  -- Nội dung tin nhắn
    AttachmentUrl  VARCHAR(500)   NULL,  -- Tệp đính kèm
    SentAt         DATETIME2(0)   NOT NULL CONSTRAINT DF_Messages_SentAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm gửi
    ReadAt         DATETIME2(0)   NULL,  -- Thời điểm đã đọc; NULL = chưa đọc
    EditedAt       DATETIME2(0)   NULL,  -- Thời điểm chỉnh sửa
    DeletedAt      DATETIME2(0)   NULL,  -- Thời điểm xóa mềm (UTC); NULL = chưa xóa
    CONSTRAINT PK_Messages PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Messages_Applications FOREIGN KEY (ApplicationId) REFERENCES dbo.Applications (Id),
    CONSTRAINT FK_Messages_SenderUser FOREIGN KEY (SenderUserId) REFERENCES dbo.Users (Id)
);
CREATE CLUSTERED INDEX CX_Messages_App_SentAt ON dbo.Messages (ApplicationId, SentAt);
CREATE INDEX IX_Messages_SenderUserId ON dbo.Messages (SenderUserId);
GO

/* =====================================================================
   6. AI MATCHING
   ===================================================================== */

-- MatchingResults: Kết quả AI chấm điểm mức độ phù hợp giữa CV và tin tuyển dụng. Giữ lịch sử, IsLatest đánh dấu kết quả mới nhất. Chỉ mang tính tham khảo.
CREATE TABLE dbo.MatchingResults (
    Id               UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    CVId             UNIQUEIDENTIFIER NOT NULL,  -- Phiên bản CV
    JobPostingId     UNIQUEIDENTIFIER NOT NULL,  -- Tin tuyển dụng
    ApplicationId    UNIQUEIDENTIFIER NULL,  -- Hồ sơ ứng tuyển (nếu điểm tính cho hồ sơ đã nộp)
    Score            DECIMAL(5,2)   NOT NULL,  -- Điểm phù hợp tổng (0-100)
    SkillScore       DECIMAL(5,2)   NULL,  -- Điểm kỹ năng
    ExperienceScore  DECIMAL(5,2)   NULL,  -- Điểm kinh nghiệm
    EducationScore   DECIMAL(5,2)   NULL,  -- Điểm học vấn
    ModelVersion     VARCHAR(50)    NOT NULL,  -- Phiên bản mô hình AI
    [Trigger]        TINYINT        NOT NULL,  -- Sự kiện kích hoạt việc tính điểm. 1 CVUploaded, 2 PostingPublished, 3 Applied, 4 Manual, 5 ModelUpgrade
    Explanation      NVARCHAR(2000) NULL,  -- Giải thích của AI
    IsLatest         BIT            NOT NULL CONSTRAINT DF_MatchingResults_IsLatest DEFAULT (1),  -- Kết quả mới nhất cho cặp CV - tin tuyển dụng
    ComputedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_MatchingResults_ComputedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tính (UTC)
    CONSTRAINT PK_MatchingResults PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_MatchingResults_CVs FOREIGN KEY (CVId) REFERENCES dbo.CVs (Id),
    CONSTRAINT FK_MatchingResults_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id),
    CONSTRAINT FK_MatchingResults_Applications FOREIGN KEY (ApplicationId) REFERENCES dbo.Applications (Id),
    CONSTRAINT CK_MatchingResults_Score CHECK (Score BETWEEN 0 AND 100),
    CONSTRAINT CK_MatchingResults_SubScores CHECK (
        (SkillScore IS NULL OR SkillScore BETWEEN 0 AND 100) AND
        (ExperienceScore IS NULL OR ExperienceScore BETWEEN 0 AND 100) AND
        (EducationScore IS NULL OR EducationScore BETWEEN 0 AND 100)),
    CONSTRAINT CK_MatchingResults_Trigger CHECK ([Trigger] BETWEEN 1 AND 5)
);
CREATE CLUSTERED INDEX CX_MatchingResults_Posting_ComputedAt ON dbo.MatchingResults (JobPostingId, ComputedAt);
CREATE UNIQUE INDEX UQ_MatchingResults_Latest ON dbo.MatchingResults (CVId, JobPostingId) WHERE IsLatest = 1;
CREATE INDEX IX_MatchingResults_RankedApplicants ON dbo.MatchingResults (JobPostingId, IsLatest, Score DESC) INCLUDE (CVId, ApplicationId);
CREATE INDEX IX_MatchingResults_Recommendations ON dbo.MatchingResults (CVId, IsLatest, Score DESC) INCLUDE (JobPostingId);
CREATE INDEX IX_MatchingResults_ApplicationId ON dbo.MatchingResults (ApplicationId);

-- MatchingResultSkills: Giải thích điểm phù hợp theo từng kỹ năng: khớp, thiếu, dư.
CREATE TABLE dbo.MatchingResultSkills (
    MatchingResultId  UNIQUEIDENTIFIER NOT NULL,  -- Kết quả so khớp
    SkillId           UNIQUEIDENTIFIER NOT NULL,  -- Kỹ năng
    MatchType         TINYINT        NOT NULL,  -- Loại so khớp. 1 Matched, 2 Missing, 3 Extra
    Weight            DECIMAL(5,4)   NULL,  -- Trọng số của kỹ năng
    CONSTRAINT PK_MatchingResultSkills PRIMARY KEY (MatchingResultId, SkillId),
    CONSTRAINT FK_MatchingResultSkills_MatchingResults FOREIGN KEY (MatchingResultId) REFERENCES dbo.MatchingResults (Id) ON DELETE CASCADE,
    CONSTRAINT FK_MatchingResultSkills_Skills FOREIGN KEY (SkillId) REFERENCES dbo.Skills (Id),
    CONSTRAINT CK_MatchingResultSkills_MatchType CHECK (MatchType BETWEEN 1 AND 3)
);
CREATE INDEX IX_MatchingResultSkills_SkillId ON dbo.MatchingResultSkills (SkillId);

-- AISuggestions: Gợi ý của AI để cải thiện CV hoặc thư giới thiệu cho một tin tuyển dụng.
CREATE TABLE dbo.AISuggestions (
    Id                UNIQUEIDENTIFIER NOT NULL,  -- Khóa chính (UUIDv7 do ứng dụng sinh)
    StudentProfileId  UNIQUEIDENTIFIER NOT NULL,  -- Sinh viên
    CVId              UNIQUEIDENTIFIER NULL,  -- CV được góp ý (nếu có)
    JobPostingId      UNIQUEIDENTIFIER NULL,  -- Tin tuyển dụng mục tiêu (nếu có)
    TargetType        TINYINT        NOT NULL,  -- Đối tượng góp ý. 1 CV, 2 CoverLetter
    InputText         NVARCHAR(MAX)  NULL,  -- Văn bản đầu vào (vd. bản nháp thư giới thiệu)
    SuggestionText    NVARCHAR(MAX)  NOT NULL,  -- Nội dung gợi ý của AI
    ModelVersion      VARCHAR(50)    NOT NULL,  -- Phiên bản mô hình AI
    Rating            TINYINT        NULL,  -- Đánh giá của sinh viên (1-5)
    CreatedAt         DATETIME2(0)   NOT NULL CONSTRAINT DF_AISuggestions_CreatedAt DEFAULT (SYSUTCDATETIME()),  -- Thời điểm tạo (UTC)
    CONSTRAINT PK_AISuggestions PRIMARY KEY (Id),
    CONSTRAINT FK_AISuggestions_StudentProfiles FOREIGN KEY (StudentProfileId) REFERENCES dbo.StudentProfiles (Id),
    CONSTRAINT FK_AISuggestions_CVs FOREIGN KEY (CVId) REFERENCES dbo.CVs (Id),
    CONSTRAINT FK_AISuggestions_JobPostings FOREIGN KEY (JobPostingId) REFERENCES dbo.JobPostings (Id),
    CONSTRAINT CK_AISuggestions_TargetType CHECK (TargetType BETWEEN 1 AND 2),
    CONSTRAINT CK_AISuggestions_Rating CHECK (Rating IS NULL OR Rating BETWEEN 1 AND 5),
    CONSTRAINT CK_AISuggestions_Input CHECK (CVId IS NOT NULL OR InputText IS NOT NULL)
);
CREATE INDEX IX_AISuggestions_StudentProfileId ON dbo.AISuggestions (StudentProfileId, CreatedAt);
CREATE INDEX IX_AISuggestions_CVId ON dbo.AISuggestions (CVId);
CREATE INDEX IX_AISuggestions_JobPostingId ON dbo.AISuggestions (JobPostingId);
GO

/* =====================================================================
   SEED DATA
   Provinces / Wards are NOT seeded here: load them with the
   provinces.open-api.vn v2 sync job (see design doc, section 5.2).
   ===================================================================== */

INSERT INTO dbo.ApplicationStatuses (Id, Code, NameVi, NameEn, SortOrder, IsFinal) VALUES
 (1, 'SUBMITTED',    N'Đã nộp',          N'Submitted',    1, 0),
 (2, 'REVIEWING',    N'Đang xem xét',    N'Reviewing',    2, 0),
 (3, 'INTERVIEWING', N'Phỏng vấn',       N'Interviewing', 3, 0),
 (4, 'OFFERED',      N'Đã đề nghị',      N'Offered',      4, 0),
 (5, 'HIRED',        N'Đã tuyển',        N'Hired',        5, 1),
 (6, 'REJECTED',     N'Từ chối',         N'Rejected',     6, 1),
 (7, 'WITHDRAWN',    N'Đã rút hồ sơ',    N'Withdrawn',    7, 1);

-- Id cố định dạng UUIDv7 để ứng dụng tham chiếu các vai trò
INSERT INTO dbo.Roles (Id, Name, NormalizedName, ConcurrencyStamp) VALUES
 ('0193a000-0000-7000-8000-000000000001', N'Admin',    N'ADMIN',    CONVERT(NVARCHAR(36), NEWID())),
 ('0193a000-0000-7000-8000-000000000002', N'Employer', N'EMPLOYER', CONVERT(NVARCHAR(36), NEWID())),
 ('0193a000-0000-7000-8000-000000000003', N'Student',  N'STUDENT',  CONVERT(NVARCHAR(36), NEWID()));

INSERT INTO dbo.Industries (Id, Code, NameVi, NameEn) VALUES
 ('0193a000-0000-7000-8000-000000000101', 'IT',           N'Công nghệ thông tin',      N'Information Technology'),
 ('0193a000-0000-7000-8000-000000000102', 'FINANCE',      N'Tài chính - Ngân hàng',    N'Finance & Banking'),
 ('0193a000-0000-7000-8000-000000000103', 'MARKETING',    N'Marketing - Truyền thông', N'Marketing & Communications'),
 ('0193a000-0000-7000-8000-000000000104', 'ACCOUNTING',   N'Kế toán - Kiểm toán',      N'Accounting & Auditing'),
 ('0193a000-0000-7000-8000-000000000105', 'EDUCATION',    N'Giáo dục - Đào tạo',       N'Education & Training'),
 ('0193a000-0000-7000-8000-000000000106', 'MANUFACTURING',N'Sản xuất',                 N'Manufacturing'),
 ('0193a000-0000-7000-8000-000000000107', 'LOGISTICS',    N'Logistics - Vận tải',      N'Logistics & Transport'),
 ('0193a000-0000-7000-8000-000000000108', 'HOSPITALITY',  N'Nhà hàng - Khách sạn',     N'Hospitality'),
 ('0193a000-0000-7000-8000-000000000109', 'HEALTHCARE',   N'Y tế',                     N'Healthcare'),
 ('0193a000-0000-7000-8000-000000000110', 'OTHER',        N'Khác',                     N'Other');

INSERT INTO dbo.Skills (Id, Name, NormalizedName, Category, IsApproved) VALUES
 ('0193a000-0000-7000-8000-000000000201', N'C#',            N'C#',            1, 1),
 ('0193a000-0000-7000-8000-000000000202', N'ASP.NET Core',  N'ASP.NET CORE',  1, 1),
 ('0193a000-0000-7000-8000-000000000203', N'SQL Server',    N'SQL SERVER',    1, 1),
 ('0193a000-0000-7000-8000-000000000204', N'JavaScript',    N'JAVASCRIPT',    1, 1),
 ('0193a000-0000-7000-8000-000000000205', N'React',         N'REACT',         1, 1),
 ('0193a000-0000-7000-8000-000000000206', N'Python',        N'PYTHON',        1, 1),
 ('0193a000-0000-7000-8000-000000000207', N'Git',           N'GIT',           4, 1),
 ('0193a000-0000-7000-8000-000000000208', N'Giao tiếp',     N'GIAO TIẾP',     2, 1),
 ('0193a000-0000-7000-8000-000000000209', N'Làm việc nhóm', N'LÀM VIỆC NHÓM', 2, 1),
 ('0193a000-0000-7000-8000-000000000210', N'Tiếng Anh',     N'TIẾNG ANH',     3, 1);
GO

PRINT N'RecruitmentPortal database created.';
GO
