Use this script as follows:

```
./stardog-install-maven.sh <your stardog lib dir>
```

Add the following dependency to your project's pom.xml:

```
<dependency>
  <groupId>com.clarkparsia</groupId>
  <artifactId>stardog-libs</artifactId>
  <version>${stardog.version}</version>
  <type>pom</type>
</dependency>
```

