class PublicInbox < Formula
  desc "Archive-first mailing-list toolkit, including lei"
  homepage "https://public-inbox.org/"
  url "https://public-inbox.org/public-inbox.git/snapshot/public-inbox-2.1.0.tar.gz"
  sha256 "03da8788e62e24e5230eabb8ea0a7206e95ee3716c810107d05ee66995236deb"
  license "AGPL-3.0-or-later"

  # FORMULA_SCAFFOLD_INCOMPLETE
  # Remove this only after the portability patch is pinned and the functional
  # test passes on macOS and Linux.
  disable! date: "2026-08-30", because: "requires an unpinned macOS IPC portability patch"

  # pkgconf is needed at runtime when XapHelperCxx builds its per-user cache.
  depends_on "git"
  depends_on "openssl@3"
  depends_on "perl"
  depends_on "pkgconf"
  depends_on "sqlite"
  depends_on "xapian"
  uses_from_macos "curl"

  on_linux do
    depends_on "zlib-ng-compat"
  end

  # Homebrew's xapian formula does not install the Perl binding. Keep this
  # resource exactly aligned with Formula["xapian"].version.
  resource "xapian-bindings" do
    url "https://oligarchy.co.uk/xapian/2.1.0/xapian-bindings-2.1.0.tar.xz"
    sha256 "f52ec189f13b4fa66ea625a6eb94bb32dd651b9ec806be6a911dda54cbe3875c"
  end

  # TODO(PORTABILITY): Add the immutable, upstreamable macOS IPC patch after
  # its commit and downloaded patch have been verified. Do not pin a branch.
  #
  # patch do
  #   url "https://github.com/tdmackey/public-inbox/commit/<FULL_COMMIT_SHA>.patch?full_index=1"
  #   sha256 "<PATCH_SHA256>"
  # end

  # Runtime/build closure for the upstream `lei` dependency profile. These are
  # ordered so every non-core prerequisite is installed before its consumer.
  resource "MIME-Base32" do
    url "https://cpan.metacpan.org/authors/id/R/RE/REHSACK/MIME-Base32-1.303.tar.gz"
    sha256 "ab21fa99130e33a0aff6cdb596f647e5e565d207d634ba2ef06bdbef50424e99"
  end

  resource "URI" do
    url "https://cpan.metacpan.org/authors/id/O/OA/OALDERS/URI-5.36.tar.gz"
    sha256 "32719e57413db6e18492e104707b95c2210df637614c512e7368c9ec3c2f783b"
  end

  resource "DBI" do
    url "https://cpan.metacpan.org/authors/id/H/HM/HMBRAND/DBI-1.652.tgz"
    sha256 "e7981833696d15414bb76c43817d48f9fc3879e1421433116374fbc63e8e78ad"
  end

  resource "DBD-SQLite" do
    url "https://cpan.metacpan.org/authors/id/I/IS/ISHIGAKI/DBD-SQLite-1.78.tar.gz"
    sha256 "efbad7794bafaa4e7476c07445a33bbfe1040e380baa3395a02635eebe3859d5"
  end

  resource "File-ShareDir-Install" do
    url "https://cpan.metacpan.org/authors/id/E/ET/ETHER/File-ShareDir-Install-0.14.tar.gz"
    sha256 "8f9533b198f2d4a9a5288cbc7d224f7679ad05a7a8573745599789428bc5aea0"
  end

  resource "YAML-PP" do
    url "https://cpan.metacpan.org/authors/id/T/TI/TINITA/YAML-PP-v0.41.0.tar.gz"
    sha256 "3ddfb2bdd2e7ef2d949dbd8ffb51439164c84d22bff615e47dbd8ea48ba75cae"
  end

  resource "XXX" do
    url "https://cpan.metacpan.org/authors/id/I/IN/INGY/XXX-0.38.tar.gz"
    sha256 "d10510ea00f619abf47ab299f148bd5b360cfa07dc0ed518138b7cec72692d2a"
  end

  resource "Pegex" do
    url "https://cpan.metacpan.org/authors/id/I/IN/INGY/Pegex-0.75.tar.gz"
    sha256 "4dc8d335de80b25247cdb3f946f0d10d9ba0b3c34b0ed7d00316fd068fd05edc"
  end

  resource "Parse-RecDescent" do
    url "https://cpan.metacpan.org/authors/id/J/JT/JTBRAUN/Parse-RecDescent-1.967015.tar.gz"
    sha256 "1943336a4cb54f1788a733f0827c0c55db4310d5eae15e542639c9dd85656e37"
  end

  resource "Inline" do
    url "https://cpan.metacpan.org/authors/id/I/IN/INGY/Inline-0.87.tar.gz"
    sha256 "105e4271ace1c1b5a264d771ff111d8b928b256002888222862c7be9686f39c5"
  end

  resource "Inline-C" do
    url "https://cpan.metacpan.org/authors/id/E/ET/ETJ/Inline-C-0.82.tar.gz"
    sha256 "10fbcf1e158d1c8d77e1dd934e379165b126a45c13645ad0be9dc07d151dd0cc"
  end

  resource "Net-SSLeay" do
    url "https://cpan.metacpan.org/authors/id/C/CH/CHRISN/Net-SSLeay-1.96.tar.gz"
    sha256 "ab213691685fb2a576c669cbc8d9266f8165a31563ad15b7c4030b94adfc0753"
  end

  resource "IO-Socket-SSL" do
    url "https://cpan.metacpan.org/authors/id/S/SU/SULLR/IO-Socket-SSL-2.099.tar.gz"
    sha256 "a0be800ff4852b1567ee5500e772417ad7a360abff80c01b5b875c15d44be832"
  end

  resource "Mail-IMAPClient" do
    url "https://cpan.metacpan.org/authors/id/P/PL/PLOBBES/Mail-IMAPClient-3.43.tar.gz"
    sha256 "093c97fac15b47a8fe4d2936ef2df377abf77cc8ab74092d2128bb945d1fb46f"
  end

  deny_network_access!

  def install
    perl5lib = libexec/"lib/perl5"
    script_dir = bin
    ENV["PERL_MM_USE_DEFAULT"] = "1"
    ENV["NO_NETWORK_TESTING"] = "1"
    ENV["OPENSSL_PREFIX"] = formula_opt_prefix("openssl@3")
    ENV.prepend_path "PATH", formula_opt_bin("openssl@3")
    ENV.prepend_create_path "PERL5LIB", perl5lib
    runtime_perl5lib = perl5lib.to_s

    if Formula["xapian"].version != resource("xapian-bindings").version
      odie "xapian-bindings resource needs to be updated"
    end

    resource("xapian-bindings").stage do
      ENV["PERL"] = formula_opt_bin("perl")/"perl"
      ENV["PERL_ARCH"] = perl5lib
      ENV["PERL_LIB"] = perl5lib
      ENV["XAPIAN_CONFIG"] = formula_opt_bin("xapian")/"xapian-config"

      system "./configure", *std_configure_args, "--disable-silent-rules", "--with-perl"
      system "make"
      system "make", "install"
    end

    # CPAN resources must be declared above in dependency order. Keep the
    # separately configured xapian-bindings resource out of this MakeMaker loop.
    resources.reject { |resource| resource.name == "xapian-bindings" }.each do |resource|
      resource.stage do
        if File.exist? "Makefile.PL"
          args = ["INSTALL_BASE=#{libexec}"]
          if resource.name == "DBD-SQLite"
            # Upstream intentionally leaves system SQLite selection to
            # downstream packagers. Enable its guarded SQLITE_LOCATION path.
            inreplace "Makefile.PL", "if ( 0 ) {", "if ( 1 ) {"
            args << "SQLITE_LOCATION=#{formula_opt_prefix("sqlite")}"
          end
          system "perl", "Makefile.PL", *args
          system "make"
          system "make", "install"
        elsif File.exist? "Build.PL"
          system "perl", "Build.PL", "--install_base", libexec
          system "./Build"
          system "./Build", "install"
        else
          odie "Unsupported Perl resource build system: #{resource.name}"
        end
      end
    end

    # Install into bin first; env_script_all_files moves the scripts under
    # libexec and replaces them with wrappers carrying the packaged PERL5LIB.
    system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}",
                                 "INSTALLSCRIPT=#{script_dir}",
                                 "INSTALLSITESCRIPT=#{script_dir}",
                                 "INSTALLSITEMAN1DIR=#{man1}",
                                 "INSTALLSITEMAN3DIR=#{man3}"
    system "make"
    system "make", "install"

    %w[lei public-inbox-init].each do |executable|
      odie "#{executable} was not installed under #{script_dir}" unless (script_dir/executable).exist?
    end
    bin.env_script_all_files(libexec/"bin", PERL5LIB: runtime_perl5lib)
  end

  test do
    ENV["HOME"] = testpath
    runtime_dir = testpath/"run"
    ENV["XDG_RUNTIME_DIR"] = runtime_dir
    ENV.prepend_path "PERL5LIB", libexec/"lib/perl5"

    system formula_opt_bin("perl")/"perl", "-MIO::Socket::SSL",
           "-MMail::IMAPClient", "-e", "exit 0"

    inbox = testpath/"inbox"
    system bin/"public-inbox-init", "-V2", "brew-test", inbox,
           "https://example.invalid/brew-test", "brew-test@example.invalid"
    assert_path_exists inbox/"git/0.git"

    message = testpath/"message.eml"
    message.write <<~EOS
      From: Homebrew Test <sender@example.invalid>
      To: brew-test@example.invalid
      Date: Thu, 1 Jan 1970 00:00:00 +0000
      Message-ID: <homebrew-public-inbox-test@example.invalid>
      Subject: homebrew public-inbox functional test

      This message validates lei import and search.
    EOS

    begin
      system bin/"lei", "import", message
      output = shell_output("#{bin}/lei q --format=json 'm:homebrew-public-inbox-test@example.invalid'")
      assert_match "homebrew public-inbox functional test", output
    ensure
      quiet_system bin/"lei", "daemon-kill" if (runtime_dir/"lei").directory?
    end
  end
end
