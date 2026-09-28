class PublicInbox < Formula
  desc "Archive-first mailing-list toolkit, including lei"
  homepage "https://public-inbox.org/"
  url "https://github.com/tdmackey/public-inbox/releases/download/homebrew-source-7b106f5f/public-inbox-2.1.0-62-g7b106f5f.tar.gz"
  version "2.1.0-62-g7b106f5f"
  sha256 "a702d9446e6543b391ace86284cc3e4e72e49f68c0a3ebc19b18bf80be4d5993"
  license "AGPL-3.0-or-later"
  revision 1

  # This fixed source archive excludes the install/ package-manager helpers.
  # The install/ directory conflicts with INSTALL on default macOS filesystems.
  # Use an upstream release after it includes the portable IPC changes.
  livecheck do
    skip "pinned development snapshot"
  end

  # XapHelperCxx uses pkgconf to build its cache when the command runs.
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

  # Homebrew's xapian formula does not install the Perl binding.
  # Keep this resource at the same version as Formula["xapian"].
  resource "xapian-bindings" do
    url "https://oligarchy.co.uk/xapian/2.1.0/xapian-bindings-2.1.0.tar.xz"
    sha256 "f52ec189f13b4fa66ea625a6eb94bb32dd651b9ec806be6a911dda54cbe3875c"
  end

  # Install the build and runtime dependencies for upstream's lei profile.
  # Install each prerequisite before the resource that needs it.
  resource "MIME-Base32" do
    url "https://cpan.metacpan.org/authors/id/R/RE/REHSACK/MIME-Base32-1.303.tar.gz"
    sha256 "ab21fa99130e33a0aff6cdb596f647e5e565d207d634ba2ef06bdbef50424e99"
  end

  # Darwin's struct flock layout is not built into public-inbox.
  resource "File-FcntlLock" do
    url "https://cpan.metacpan.org/authors/id/J/JT/JTT/File-FcntlLock-0.22.tar.gz"
    sha256 "9a9abb2efff93ab73741a128d3f700e525273546c15d04e7c51c704ab09dbcdf"
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

  # The lei test uses a local AF_UNIX socket. The macOS network sandbox blocks
  # this socket. Block network access during the build only.
  deny_network_access! :build

  def install
    perl5lib = libexec/"lib/perl5"
    script_dir = bin
    ENV["PERL_MM_USE_DEFAULT"] = "1"
    ENV["NO_NETWORK_TESTING"] = "1"
    ENV["OPENSSL_PREFIX"] = formula_opt_prefix("openssl@3")
    ENV.prepend_path "PATH", formula_opt_bin("openssl@3")
    ENV.prepend_create_path "PERL5LIB", perl5lib
    runtime_perl5lib = perl5lib.to_s

    xapian_config = formula_opt_bin("xapian")/"xapian-config"
    xapian_version = Utils.safe_popen_read(xapian_config, "--version").split.last
    if xapian_version != resource("xapian-bindings").version.to_s
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

    # Install CPAN resources in the order above. The Xapian binding uses
    # configure, so exclude it from this loop.
    resources.reject { |resource| resource.name == "xapian-bindings" }.each do |resource|
      resource.stage do
        if File.exist? "Makefile.PL"
          args = ["INSTALL_BASE=#{libexec}"]
          if resource.name == "DBD-SQLite"
            # Enable upstream's packager option to use Homebrew's SQLite.
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

    # Install scripts in bin. Then move them to libexec/bin and add wrappers
    # that set PERL5LIB. Upstream's install-man target uses INSTALLMAN1DIR.
    system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}",
                                 "INSTALLSCRIPT=#{script_dir}",
                                 "INSTALLSITESCRIPT=#{script_dir}",
                                 "INSTALLMAN1DIR=#{man1}",
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

    system formula_opt_bin("perl")/"perl", "-I#{libexec}/lib/perl5", "-MFile::FcntlLock",
           "-MIO::Socket::SSL", "-MMail::IMAPClient", "-e", "exit 0"

    assert_path_exists man1/"lei.1"
    assert_path_exists man5/"public-inbox-config.5"
    assert_path_exists man7/"lei-overview.7"
    assert_path_exists man8/"lei-daemon.8"

    inbox = testpath/"inbox"
    system bin/"public-inbox-init", "-V2", "brew-test", inbox,
           "https://example.invalid/brew-test", "brew-test@example.invalid"
    assert_path_exists inbox/"git/0.git"
    system bin/"public-inbox-index", inbox

    # Homebrew's Linux sandbox blocks the lei/store worker from opening /.
    # Test the full daemon workflow on macOS. The source CI tests lei on Linux.
    if OS.mac?
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
end
